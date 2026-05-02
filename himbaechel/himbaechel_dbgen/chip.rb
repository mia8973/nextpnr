require 'digest'
require_relative 'bba'

class BBAStruct
  def serialise_lists(context, bba); end
  def serialise(context, bba); end
end

class IdString
  include Comparable
  attr_reader :index
  def initialize(index = 0)
    @index = index
  end
  def <=>(other)
    @index <=> other.index
  end
  def eql?(other)
    other.is_a?(IdString) && @index == other.index
  end
  def hash
    @index.hash
  end
  def ==(other)
    other.is_a?(IdString) && @index == other.index
  end
  def to_s
    "IdString(#{@index})"
  end
end

class StringPool
  attr_reader :strs, :known_id_count
  def initialize
    @strs = {"" => 0}
    @known_id_count = 1
  end

  def read_constids(file)
    idx = 1
    File.open(file, "r") do |f|
      f.each_line do |line|
        l = line.strip
        next unless l.start_with?("X(")
        l = l[2..]
        raise "expected ')', got #{l.inspect}" unless l.end_with?(")")
        l = l[0..-2].strip
        i = id(l)
        raise "expected index #{idx}, got #{i.index} for #{l.inspect}" unless i.index == idx
        idx += 1
      end
    end
    @known_id_count = idx
  end

  def id(val)
    if @strs.key?(val)
      IdString.new(@strs[val])
    else
      idx = @strs.length
      @strs[val] = idx
      IdString.new(idx)
    end
  end

  def serialise_lists(context, bba)
    bba.label("#{context}_strs")
    @strs.sort_by { |_s, i| i }.each do |s, i|
      next if i < @known_id_count
      bba.str(s)
    end
  end

  def serialise(context, bba)
    bba.u32(@known_id_count)
    bba.slice("#{context}_strs", @strs.length - @known_id_count)
  end
end

module PinType
  INPUT  = 0
  OUTPUT = 1
  INOUT  = 2
end

BEL_FLAG_GLOBAL = 0x01
BEL_FLAG_HIDDEN = 0x02

class BelPin < BBAStruct
  attr_accessor :name, :wire, :dir
  def initialize(name, wire, dir)
    @name = name; @wire = wire; @dir = dir
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@name.index)
    bba.u32(@wire)
    bba.u32(@dir)
  end
end

class BelData < BBAStruct
  attr_accessor :index, :name, :bel_type, :z, :flags, :site, :checker_idx, :pins, :extra_data
  def initialize(index:, name:, bel_type:, z:)
    @index = index; @name = name; @bel_type = bel_type; @z = z
    @flags = 0; @site = 0; @checker_idx = 0
    @pins = []; @extra_data = nil
  end
  def serialise_lists(context, bba)
    @pins.sort_by! { |p| p.name.index }
    bba.label("#{context}_pins")
    @pins.each_with_index { |pin, i| pin.serialise("#{context}_pin#{i}", bba) }
    if @extra_data
      @extra_data.serialise_lists("#{context}_extra_data", bba)
      bba.label("#{context}_extra_data")
      @extra_data.serialise("#{context}_extra_data", bba)
    end
  end
  def serialise(context, bba)
    bba.u32(@name.index)
    bba.u32(@bel_type.index)
    bba.u16(@z)
    bba.u16(0)
    bba.u32(@flags)
    bba.u32(@site)
    bba.u32(@checker_idx)
    bba.slice("#{context}_pins", @pins.length)
    if @extra_data
      bba.ref("#{context}_extra_data")
    else
      bba.u32(0)
    end
  end
end

class BelPinRef < BBAStruct
  attr_accessor :bel, :pin
  def initialize(bel, pin)
    @bel = bel; @pin = pin
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@bel)
    bba.u32(@pin.index)
  end
end

class TileWireData < BBAStruct
  attr_accessor :index, :name, :wire_type, :gfx_wire_id, :const_value,
                :flags, :timing_idx, :pips_uphill, :pips_downhill, :bel_pins
  def initialize(index:, name:, wire_type:, gfx_wire_id:, const_value: nil)
    @index = index; @name = name; @wire_type = wire_type
    @gfx_wire_id = gfx_wire_id
    @const_value = const_value || IdString.new(0)
    @flags = 0; @timing_idx = -1
    @pips_uphill = []; @pips_downhill = []; @bel_pins = []
  end
  def serialise_lists(context, bba)
    bba.label("#{context}_pips_uh")
    @pips_uphill.each { |idx| bba.u32(idx) }
    bba.label("#{context}_pips_dh")
    @pips_downhill.each { |idx| bba.u32(idx) }
    bba.label("#{context}_bel_pins")
    @bel_pins.each_with_index { |bp, i| bp.serialise("#{context}_bp#{i}", bba) }
  end
  def serialise(context, bba)
    bba.u32(@name.index)
    bba.u32(@wire_type.index)
    bba.u32(@gfx_wire_id)
    bba.u32(@const_value.index)
    bba.u32(@flags)
    bba.u32(@timing_idx)
    bba.slice("#{context}_pips_uh", @pips_uphill.length)
    bba.slice("#{context}_pips_dh", @pips_downhill.length)
    bba.slice("#{context}_bel_pins", @bel_pins.length)
  end
end

class PipData < BBAStruct
  attr_accessor :index, :src_wire, :dst_wire, :pip_type, :flags, :timing_idx, :extra_data
  def initialize(index:, src_wire:, dst_wire:, pip_type: nil, flags: 0, timing_idx: -1)
    @index = index; @src_wire = src_wire; @dst_wire = dst_wire
    @pip_type = pip_type || IdString.new(0)
    @flags = flags; @timing_idx = timing_idx
    @extra_data = nil
  end
  def serialise_lists(context, bba)
    if @extra_data
      @extra_data.serialise_lists("#{context}_extra_data", bba)
      bba.label("#{context}_extra_data")
      @extra_data.serialise("#{context}_extra_data", bba)
    end
  end
  def serialise(context, bba)
    bba.u32(@src_wire)
    bba.u32(@dst_wire)
    bba.u32(@pip_type.index)
    bba.u32(@flags)
    bba.u32(@timing_idx)
    if @extra_data
      bba.ref("#{context}_extra_data")
    else
      bba.u32(0)
    end
  end
end

class GroupData < BBAStruct
  attr_accessor :index, :name, :group_type, :group_bels, :group_wires,
                :group_pips, :group_groups, :extra_data
  def initialize(index:, name:, group_type: nil)
    @index = index; @name = name
    @group_type = group_type || IdString.new(0)
    @group_bels = []; @group_wires = []; @group_pips = []; @group_groups = []
    @extra_data = nil
  end
  def serialise_lists(context, bba)
    bba.label("#{context}_group_bels")
    @group_bels.each { |idx| bba.u32(idx) }
    bba.label("#{context}_group_wires")
    @group_wires.each { |idx| bba.u32(idx) }
    bba.label("#{context}_group_pips")
    @group_pips.each { |idx| bba.u32(idx) }
    bba.label("#{context}_group_groups")
    @group_groups.each { |idx| bba.u32(idx) }
    if @extra_data
      @extra_data.serialise_lists("#{context}_extra_data", bba)
      bba.label("#{context}_extra_data")
      @extra_data.serialise("#{context}_extra_data", bba)
    end
  end
  def serialise(context, bba)
    bba.u32(@name.index)
    bba.u32(@group_type.index)
    bba.slice("#{context}_group_bels", @group_bels.length)
    bba.slice("#{context}_group_wires", @group_wires.length)
    bba.slice("#{context}_group_pips", @group_pips.length)
    bba.slice("#{context}_group_groups", @group_groups.length)
    if @extra_data
      bba.ref("#{context}_extra_data")
    else
      bba.u32(0)
    end
  end
end

class TileType < BBAStruct
  attr_accessor :strs, :gfx_wire_ids, :tmg, :type_name,
                :bels, :pips, :wires, :groups,
                :_wire2idx, :_group2idx, :extra_data
  def initialize(strs, gfx_wire_ids, tmg, type_name)
    @strs = strs; @gfx_wire_ids = gfx_wire_ids; @tmg = tmg; @type_name = type_name
    @bels = []; @pips = []; @wires = []; @groups = []
    @_wire2idx = {}; @_group2idx = {}
    @extra_data = nil
  end

  def create_bel(name, type, z)
    bel = BelData.new(index: @bels.length, name: @strs.id(name), bel_type: @strs.id(type), z: z)
    @bels << bel
    bel
  end

  def add_bel_pin(bel, pin, wire, dir)
    pin_id = @strs.id(pin)
    wire_idx = @_wire2idx[@strs.id(wire)]
    bel.pins << BelPin.new(pin_id, wire_idx, dir)
    @wires[wire_idx].bel_pins << BelPinRef.new(bel.index, pin_id)
  end

  def create_wire(name, type = "", const_value = "")
    gfx_wire_id = @gfx_wire_ids.fetch(name, 0)
    wire = TileWireData.new(
      index: @wires.length,
      name: @strs.id(name),
      wire_type: @strs.id(type),
      gfx_wire_id: gfx_wire_id,
      const_value: @strs.id(const_value)
    )
    @_wire2idx[wire.name] = wire.index
    @wires << wire
    wire
  end

  def create_pip(src, dst, timing_class = "")
    src_idx = @_wire2idx[@strs.id(src)]
    dst_idx = @_wire2idx[@strs.id(dst)]
    pip = PipData.new(
      index: @pips.length, src_wire: src_idx, dst_wire: dst_idx,
      timing_idx: @tmg.pip_class_idx(timing_class)
    )
    @wires[src_idx].pips_downhill << pip.index
    @wires[dst_idx].pips_uphill << pip.index
    @pips << pip
    pip
  end

  def create_group(name, type)
    group = GroupData.new(index: @groups.length, name: @strs.id(name), group_type: @strs.id(type))
    @_group2idx[group.name] = group.index
    @groups << group
    group
  end

  def add_bel_to_group(bel, group)
    @groups[@_group2idx[@strs.id(group)]].group_bels << bel.index
  end

  def add_wire_to_group(wire, group)
    @groups[@_group2idx[@strs.id(group)]].group_wires << wire.index
  end

  def add_pip_to_group(pip, group)
    @groups[@_group2idx[@strs.id(group)]].group_pips << pip.index
  end

  def add_group_to_group(sub_group, group)
    @groups[@_group2idx[@strs.id(group)]].group_groups << sub_group.index
  end

  def has_wire(wire)
    @_wire2idx.key?(@strs.id(wire))
  end

  def set_wire_type(wire, type)
    @wires[@_wire2idx[@strs.id(wire)]].wire_type = @strs.id(type)
  end

  def serialise_lists(context, bba)
    @bels.each_with_index  { |b, i| b.serialise_lists("#{context}_bel#{i}", bba) }
    @wires.each_with_index { |w, i| w.serialise_lists("#{context}_wire#{i}", bba) }
    @pips.each_with_index  { |p, i| p.serialise_lists("#{context}_pip#{i}", bba) }
    @groups.each_with_index { |g, i| g.serialise_lists("#{context}_group#{i}", bba) }
    bba.label("#{context}_bels")
    @bels.each_with_index  { |b, i| b.serialise("#{context}_bel#{i}", bba) }
    bba.label("#{context}_wires")
    @wires.each_with_index { |w, i| w.serialise("#{context}_wire#{i}", bba) }
    bba.label("#{context}_pips")
    @pips.each_with_index  { |p, i| p.serialise("#{context}_pip#{i}", bba) }
    bba.label("#{context}_groups")
    @groups.each_with_index { |g, i| g.serialise("#{context}_group#{i}", bba) }
    if @extra_data
      @extra_data.serialise_lists("#{context}_extra_data", bba)
      bba.label("#{context}_extra_data")
      @extra_data.serialise("#{context}_extra_data", bba)
    end
  end

  def serialise(context, bba)
    bba.u32(@type_name.index)
    bba.slice("#{context}_bels", @bels.length)
    bba.slice("#{context}_wires", @wires.length)
    bba.slice("#{context}_pips", @pips.length)
    bba.slice("#{context}_groups", @groups.length)
    if @extra_data
      bba.ref("#{context}_extra_data")
    else
      bba.u32(0)
    end
  end
end

NodeWire = Struct.new(:x, :y, :wire)

class NodeShape < BBAStruct
  attr_accessor :wires, :timing_index
  def initialize(wires: [], timing_index: -1)
    @wires = wires.dup; @timing_index = timing_index
  end
  def key
    Digest::MD5.digest(@wires.pack("s<*") + [@timing_index].pack("l<"))
  end
  def serialise_lists(context, bba)
    bba.label("#{context}_wires")
    @wires.each { |w| bba.u16(w) }
    bba.u16(0) if @wires.length % 2 != 0
  end
  def serialise(context, bba)
    bba.slice("#{context}_wires", @wires.length / 3)
    bba.u32(@timing_index)
  end
end

MODE_TILE_WIRE = 0x7000
MODE_IS_ROOT   = 0x7001
MODE_ROW_CONST = 0x7002
MODE_GLB_CONST = 0x7003

class RelNodeRef < BBAStruct
  attr_accessor :dx_mode, :dy, :wire
  def initialize(dx_mode: MODE_TILE_WIRE, dy: 0, wire: 0)
    @dx_mode = dx_mode; @dy = dy; @wire = wire
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u16(@dx_mode); bba.u16(@dy); bba.u16(@wire)
  end
end

class TileRoutingShape < BBAStruct
  attr_accessor :wire_to_node
  def initialize
    @wire_to_node = []
  end
  def key
    Digest::MD5.digest(@wire_to_node.pack("s<*"))
  end
  def serialise_lists(context, bba)
    bba.label("#{context}_w2n")
    @wire_to_node.each { |x| bba.u16(x) }
    bba.u16(0) if @wire_to_node.length % 2 != 0
  end
  def serialise(context, bba)
    bba.slice("#{context}_w2n", @wire_to_node.length / 3)
    bba.u32(-1)
  end
end

class TileInst < BBAStruct
  attr_accessor :x, :y, :type_idx, :name_prefix, :loc_type, :shape, :shape_idx, :extra_data
  def initialize(x, y)
    @x = x; @y = y
    @type_idx = nil
    @name_prefix = IdString.new(0)
    @loc_type = 0
    @shape = TileRoutingShape.new
    @shape_idx = -1
    @extra_data = nil
  end
  def serialise_lists(context, bba)
    if @extra_data
      @extra_data.serialise_lists("#{context}_extra_data", bba)
      bba.label("#{context}_extra_data")
      @extra_data.serialise("#{context}_extra_data", bba)
    end
  end
  def serialise(context, bba)
    bba.u32(@name_prefix.index)
    bba.u32(@type_idx)
    bba.u32(@shape_idx)
    if @extra_data
      bba.ref("#{context}_extra_data")
    else
      bba.u32(0)
    end
  end
end

class PadInfo < BBAStruct
  attr_accessor :package_pin, :tile, :bel, :pad_function, :pad_bank, :flags, :extra_data
  def initialize(package_pin:, tile:, bel:, pad_function:, pad_bank:, flags:)
    @package_pin = package_pin; @tile = tile; @bel = bel
    @pad_function = pad_function; @pad_bank = pad_bank; @flags = flags
    @extra_data = nil
  end
  def serialise_lists(context, bba)
    if @extra_data
      @extra_data.serialise_lists("#{context}_extra_data", bba)
      bba.label("#{context}_extra_data")
      @extra_data.serialise("#{context}_extra_data", bba)
    end
  end
  def serialise(context, bba)
    bba.u32(@package_pin.index)
    bba.u32(@tile.index)
    bba.u32(@bel.index)
    bba.u32(@pad_function.index)
    bba.u32(@pad_bank)
    bba.u32(@flags)
    if @extra_data
      bba.ref("#{context}_extra_data")
    else
      bba.u32(0)
    end
  end
end

class PackageInfo < BBAStruct
  attr_accessor :strs, :name, :pads, :extra_data
  def initialize(strs, name)
    @strs = strs; @name = name
    @pads = []; @extra_data = nil
  end
  def create_pad(package_pin, tile, bel, pad_function, pad_bank, flags = 0)
    pad = PadInfo.new(
      package_pin: @strs.id(package_pin), tile: @strs.id(tile), bel: @strs.id(bel),
      pad_function: @strs.id(pad_function), pad_bank: pad_bank, flags: flags
    )
    @pads << pad
    pad
  end
  def serialise_lists(context, bba)
    @pads.each_with_index { |pad, i| pad.serialise_lists("#{context}_pad#{i}", bba) }
    bba.label("#{context}_pads")
    @pads.each_with_index { |pad, i| pad.serialise("#{context}_pad#{i}", bba) }
    if @extra_data
      @extra_data.serialise_lists("#{context}_extra_data", bba)
      bba.label("#{context}_extra_data")
      @extra_data.serialise("#{context}_extra_data", bba)
    end
  end
  def serialise(context, bba)
    bba.u32(@name.index)
    bba.slice("#{context}_pads", @pads.length)
    if @extra_data
      bba.ref("#{context}_extra_data")
    else
      bba.u32(0)
    end
  end
end

class TimingValue < BBAStruct
  attr_accessor :fast_min, :fast_max, :slow_min, :slow_max
  def initialize(fast_min = 0, fast_max = nil, slow_min = nil, slow_max = nil)
    @fast_min = fast_min
    @fast_max = fast_max || fast_min
    @slow_min = slow_min || @fast_min
    @slow_max = slow_max || @fast_max
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@fast_min)
    bba.u32(@fast_max)
    bba.u32(@slow_min)
    bba.u32(@slow_max)
  end
end

class PipTiming < BBAStruct
  attr_accessor :int_delay, :in_cap, :out_res, :flags
  def initialize(int_delay: nil, in_cap: nil, out_res: nil, flags: 0)
    @int_delay = int_delay || TimingValue.new
    @in_cap = in_cap || TimingValue.new
    @out_res = out_res || TimingValue.new
    @flags = flags
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    @int_delay.serialise(context, bba)
    @in_cap.serialise(context, bba)
    @out_res.serialise(context, bba)
    bba.u32(@flags)
  end
end

class NodeTiming < BBAStruct
  attr_accessor :res, :cap, :delay
  def initialize(res: nil, cap: nil, delay: nil)
    @res = res || TimingValue.new
    @cap = cap || TimingValue.new
    @delay = delay || TimingValue.new
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    @res.serialise(context, bba)
    @cap.serialise(context, bba)
    @delay.serialise(context, bba)
  end
end

module ClockEdge
  RISING  = 0
  FALLING = 1
end

class CellPinRegArc < BBAStruct
  attr_accessor :clock, :edge, :setup, :hold, :clk_q
  def initialize(clock:, edge:, setup: nil, hold: nil, clk_q: nil)
    @clock = clock; @edge = edge
    @setup = setup || TimingValue.new
    @hold  = hold  || TimingValue.new
    @clk_q = clk_q || TimingValue.new
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@clock.index)
    bba.u32(@edge)
    @setup.serialise(context, bba)
    @hold.serialise(context, bba)
    @clk_q.serialise(context, bba)
  end
end

class CellPinCombArc < BBAStruct
  attr_accessor :from_pin, :delay
  def initialize(from_pin:, delay: nil)
    @from_pin = from_pin
    @delay = delay || TimingValue.new
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@from_pin.index)
    @delay.serialise(context, bba)
  end
end

class CellPinTiming < BBAStruct
  attr_accessor :pin, :flags, :comb_arcs, :reg_arcs
  def initialize(pin:)
    @pin = pin; @flags = 0
    @comb_arcs = []; @reg_arcs = []
  end
  def set_clock
    @flags |= 1
  end
  def finalise
    @comb_arcs.sort_by! { |a| a.from_pin.index }
    @reg_arcs.sort_by!  { |a| a.clock.index }
  end
  def serialise_lists(context, bba)
    bba.label("#{context}_comb")
    @comb_arcs.each_with_index { |a, i| a.serialise("#{context}_comb#{i}", bba) }
    bba.label("#{context}_reg")
    @reg_arcs.each_with_index  { |a, i| a.serialise("#{context}_reg#{i}", bba) }
  end
  def serialise(context, bba)
    bba.u32(@pin.index)
    bba.u32(@flags)
    bba.slice("#{context}_comb", @comb_arcs.length)
    bba.slice("#{context}_reg", @reg_arcs.length)
  end
end

class CellTiming < BBAStruct
  attr_accessor :strs, :type_variant, :pin_data, :pins
  def initialize(strs, type_variant)
    @strs = strs
    @type_variant = strs.id(type_variant)
    @pin_data = {}
    @pins = []
  end

  def add_comb_arc(from_pin, to_pin, delay)
    @pin_data[to_pin] ||= CellPinTiming.new(pin: @strs.id(to_pin))
    @pin_data[to_pin].comb_arcs << CellPinCombArc.new(from_pin: @strs.id(from_pin), delay: delay)
  end

  def add_setup_hold(clock, input_pin, edge, setup, hold)
    @pin_data[input_pin] ||= CellPinTiming.new(pin: @strs.id(input_pin))
    @pin_data[clock]     ||= CellPinTiming.new(pin: @strs.id(clock))
    @pin_data[input_pin].reg_arcs << CellPinRegArc.new(clock: @strs.id(clock), edge: edge, setup: setup, hold: hold)
    @pin_data[clock].set_clock
  end

  def add_clock_out(clock, output_pin, edge, delay)
    @pin_data[output_pin] ||= CellPinTiming.new(pin: @strs.id(output_pin))
    @pin_data[clock]      ||= CellPinTiming.new(pin: @strs.id(clock))
    @pin_data[output_pin].reg_arcs << CellPinRegArc.new(clock: @strs.id(clock), edge: edge, clk_q: delay)
    @pin_data[clock].set_clock
  end

  def finalise
    @pins = @pin_data.values
    @pins.sort_by! { |p| p.pin.index }
    @pins.each(&:finalise)
  end

  def serialise_lists(context, bba)
    @pins.each_with_index { |p, i| p.serialise_lists("#{context}_pin#{i}", bba) }
    bba.label("#{context}_pins")
    @pins.each_with_index { |p, i| p.serialise("#{context}_pin#{i}", bba) }
  end

  def serialise(context, bba)
    bba.u32(@type_variant.index)
    bba.slice("#{context}_pins", @pins.length)
  end
end

class SpeedGrade < BBAStruct
  attr_accessor :name, :pip_classes, :node_classes, :cell_types, :extra_data
  def initialize(name:)
    @name = name
    @pip_classes = []; @node_classes = []; @cell_types = []
    @extra_data = nil
  end
  def finalise
    @cell_types.sort_by! { |ty| ty.type_variant.index }
    @cell_types.each(&:finalise)
  end
  def serialise_lists(context, bba)
    @cell_types.each_with_index { |t, i| t.serialise_lists("#{context}_cellty#{i}", bba) }
    bba.label("#{context}_pip_classes")
    @pip_classes.each_with_index { |p, i| p.serialise("#{context}_pipc#{i}", bba) }
    bba.label("#{context}_node_classes")
    @node_classes.each_with_index { |n, i| n.serialise("#{context}_nodec#{i}", bba) }
    bba.label("#{context}_cell_types")
    @cell_types.each_with_index { |t, i| t.serialise("#{context}_cellty#{i}", bba) }
    if @extra_data
      @extra_data.serialise_lists("#{context}_extra_data", bba)
      bba.label("#{context}_extra_data")
      @extra_data.serialise("#{context}_extra_data", bba)
    end
  end
  def serialise(context, bba)
    bba.u32(@name.index)
    bba.slice("#{context}_pip_classes", @pip_classes.length)
    bba.slice("#{context}_node_classes", @node_classes.length)
    bba.slice("#{context}_cell_types", @cell_types.length)
    if @extra_data
      bba.ref("#{context}_extra_data")
    else
      bba.u32(0)
    end
  end
end

class TimingPool
  attr_accessor :strs, :speed_grades, :speed_grade_idx, :pip_classes, :node_classes
  def initialize(strs)
    @strs = strs
    @speed_grades = []
    @speed_grade_idx = {}
    @pip_classes = {}
    @node_classes = {}
  end

  def set_speed_grades(speed_grades)
    raise "speed grades already set" unless @speed_grades.empty?
    @speed_grades = speed_grades.map { |g| SpeedGrade.new(name: @strs.id(g)) }
    speed_grades.each_with_index { |g, i| @speed_grade_idx[g] = i }
  end

  def pip_class_idx(name)
    return -1 if name == ""
    if @pip_classes.key?(name)
      @pip_classes[name]
    else
      idx = @pip_classes.length
      @pip_classes[name] = idx
      idx
    end
  end

  def node_class_idx(name)
    return -1 if name == ""
    if @node_classes.key?(name)
      @node_classes[name]
    else
      idx = @node_classes.length
      @node_classes[name] = idx
      idx
    end
  end

  def set_pip_class(grade:, name:, delay:, in_cap: nil, out_res: nil, is_buffered: true)
    idx = pip_class_idx(name)
    sg = @speed_grades[@speed_grade_idx[grade]]
    sg.pip_classes << nil while idx >= sg.pip_classes.length
    raise "attempting to set pip class #{name} in speed grade #{grade} twice" unless sg.pip_classes[idx].nil?
    sg.pip_classes[idx] = PipTiming.new(
      int_delay: delay,
      in_cap: in_cap || TimingValue.new,
      out_res: out_res || TimingValue.new,
      flags: (is_buffered ? 1 : 0)
    )
  end

  def set_bel_pin_class(grade:, name:, delay:, in_cap: nil, out_res: nil)
    set_pip_class(grade: grade, name: name, delay: delay, in_cap: in_cap, out_res: out_res, is_buffered: true)
  end

  def set_node_class(grade:, name:, delay:, res: nil, cap: nil)
    idx = node_class_idx(name)
    sg = @speed_grades[@speed_grade_idx[grade]]
    sg.node_classes << nil while idx >= sg.node_classes.length
    raise "attempting to set node class #{name} in speed grade #{grade} twice" unless sg.node_classes[idx].nil?
    sg.node_classes[idx] = NodeTiming.new(delay: delay, res: res || TimingValue.new, cap: cap || TimingValue.new)
  end

  def add_cell_variant(speed_grade, name)
    cell = CellTiming.new(@strs, name)
    @speed_grades[@speed_grade_idx[speed_grade]].cell_types << cell
    cell
  end

  def get_speed_grade(grade)
    @speed_grades[@speed_grade_idx[grade]]
  end

  def finalise
    @speed_grades.each(&:finalise)
  end
end

class Chip
  attr_accessor :strs, :uarch, :name, :width, :height,
                :tile_types, :tiles, :tile_type_idx,
                :node_shapes, :node_shape_idx,
                :tile_shapes, :tile_shapes_idx,
                :packages, :extra_data, :timing, :gfx_wire_ids

  def initialize(uarch, name, width, height)
    @strs = StringPool.new
    @uarch = uarch; @name = name; @width = width; @height = height
    @tile_types = []
    @tiles = Array.new(height) { |y| Array.new(width) { |x| TileInst.new(x, y) } }
    @tile_type_idx = {}
    @node_shapes = []; @node_shape_idx = {}
    @tile_shapes  = []; @tile_shapes_idx = {}
    @packages = []
    @extra_data = nil
    @timing = TimingPool.new(@strs)
    @gfx_wire_ids = {}
  end

  def create_tile_type(name)
    tt = TileType.new(@strs, @gfx_wire_ids, @timing, @strs.id(name))
    @tile_type_idx[name] = @tile_types.length
    @tile_types << tt
    tt
  end

  def set_tile_type(x, y, type)
    @tiles[y][x].type_idx = @tile_type_idx[type]
    @tiles[y][x]
  end

  def tile_type_at(x, y)
    raise "tile type at (#{x}, #{y}) must be set" if @tiles[y][x].type_idx.nil?
    @tile_types[@tiles[y][x].type_idx]
  end

  def set_speed_grades(speed_grades)
    @timing.set_speed_grades(speed_grades)
    @timing
  end

  def add_node(wires, timing_class: "")
    twos = ->(x) { (x & 0x8000) != 0 ? x - 0x10000 : x }
    x0 = wires[0].x
    y0 = wires[0].y
    shape = NodeShape.new(timing_index: @timing.node_class_idx(timing_class))
    wires.each do |w|
      wire_index = if w.wire.is_a?(Integer)
        w.wire
      else
        wire_id = w.wire.is_a?(IdString) ? w.wire : @strs.id(w.wire)
        tile_type_at(w.x, w.y)._wire2idx[wire_id]
      end
      shape.wires += [w.x - x0, w.y - y0, wire_index]
    end
    key = shape.key
    shape_idx = if @node_shape_idx.key?(key)
      @node_shape_idx[key]
    else
      idx = @node_shapes.length
      @node_shape_idx[key] = idx
      @node_shapes << shape
      idx
    end
    wires.each_with_index do |w, i|
      inst = @tiles[w.y][w.x]
      wire_idx = shape.wires[i * 3 + 2]
      inst.shape.wire_to_node += [MODE_TILE_WIRE, 0, 0] while 3 * wire_idx >= inst.shape.wire_to_node.length
      if i == 0
        raise "attempting to add wire to multiple nodes!" unless inst.shape.wire_to_node[3 * wire_idx] == MODE_TILE_WIRE
        inst.shape.wire_to_node[3 * wire_idx]     = MODE_IS_ROOT
        inst.shape.wire_to_node[3 * wire_idx + 1] = twos.call(shape_idx & 0xFFFF)
        inst.shape.wire_to_node[3 * wire_idx + 2] = (shape_idx >> 16) & 0xFFFF
      else
        dx = x0 - w.x
        dy = y0 - w.y
        raise "dx range causes overlap with magic values!" unless dx < MODE_TILE_WIRE
        raise "attempting to add wire to multiple nodes!" unless inst.shape.wire_to_node[3 * wire_idx] == MODE_TILE_WIRE
        inst.shape.wire_to_node[3 * wire_idx]     = dx
        inst.shape.wire_to_node[3 * wire_idx + 1] = dy
        inst.shape.wire_to_node[3 * wire_idx + 2] = shape.wires[2]
      end
    end
  end

  def flatten_tile_shapes
    puts "Deduplicating tile shapes..."
    @tiles.each do |row|
      row.each do |tile|
        key = tile.shape.key
        if @tile_shapes_idx.key?(key)
          tile.shape_idx = @tile_shapes_idx[key]
        else
          tile.shape_idx = @tile_shapes.length
          @tile_shapes << tile.shape
          @tile_shapes_idx[key] = tile.shape_idx
        end
      end
    end
    puts "#{@tile_shapes.length} unique tile routing shapes"
  end

  def create_package(name)
    pkg = PackageInfo.new(@strs, @strs.id(name))
    @packages << pkg
    pkg
  end

  def serialise(bba)
    flatten_tile_shapes
    @tile_types.each_with_index  { |tt, i|  tt.serialise_lists("tt#{i}", bba) }
    @node_shapes.each_with_index { |s, i|   s.serialise_lists("nshp#{i}", bba) }
    @tile_shapes.each_with_index { |ts, i|  ts.serialise_lists("tshp#{i}", bba) }
    @packages.each_with_index    { |pkg, i| pkg.serialise_lists("pkg#{i}", bba) }
    @tiles.each_with_index do |row, y|
      row.each_with_index { |ti, x| ti.serialise_lists("tinst_#{x}_#{y}", bba) }
    end
    @timing.speed_grades.each_with_index { |sg, i| sg.serialise_lists("sg#{i}", bba) }
    @strs.serialise_lists("constids", bba)
    if @extra_data
      @extra_data.serialise_lists("extra_data", bba)
      bba.label("extra_data")
      @extra_data.serialise("extra_data", bba)
    end

    bba.label("tile_types")
    @tile_types.each_with_index  { |tt, i|  tt.serialise("tt#{i}", bba) }
    bba.label("node_shapes")
    @node_shapes.each_with_index { |s, i|   s.serialise("nshp#{i}", bba) }
    bba.label("tile_shapes")
    @tile_shapes.each_with_index { |ts, i|  ts.serialise("tshp#{i}", bba) }
    bba.label("packages")
    @packages.each_with_index    { |pkg, i| pkg.serialise("pkg#{i}", bba) }
    bba.label("tile_insts")
    @tiles.each_with_index do |row, y|
      row.each_with_index { |ti, x| ti.serialise("tinst_#{x}_#{y}", bba) }
    end
    bba.label("speed_grades")
    @timing.speed_grades.each_with_index { |sg, i| sg.serialise("sg#{i}", bba) }
    bba.label("constids")
    @strs.serialise("constids", bba)

    bba.label("chip_info")
    bba.u32(0x00ca7ca7)
    bba.u32(6)
    bba.u32(@width)
    bba.u32(@height)
    bba.str(@uarch)
    bba.str(@name)
    bba.str("ruby_dbgen")
    bba.slice("tile_types", @tile_types.length)
    bba.slice("tile_insts", @width * @height)
    bba.slice("node_shapes", @node_shapes.length)
    bba.slice("tile_shapes", @tile_shapes.length)
    bba.slice("packages", @packages.length)
    bba.slice("speed_grades", @timing.speed_grades.length)
    bba.ref("constids")
    if @extra_data
      bba.ref("extra_data")
    else
      bba.u32(0)
    end
  end

  def write_bba(filename)
    @timing.finalise
    File.open(filename, "w") do |f|
      bba = BBAWriter.new(f)
      bba.pre('#include "nextpnr.h"')
      bba.pre('NEXTPNR_NAMESPACE_BEGIN')
      bba.post('NEXTPNR_NAMESPACE_END')
      bba.push('chipdb_blob')
      bba.ref('chip_info')
      serialise(bba)
      bba.pop
    end
  end

  def read_gfxids(filename)
    idx = 1
    File.open(filename) do |f|
      f.each_line do |line|
        l = line.strip
        next unless l.start_with?("X(")
        l = l[2..]
        raise "expected ')'" unless l.end_with?(")")
        l = l[0..-2].strip
        @gfx_wire_ids[l] = idx
        idx += 1
      end
    end
  end
end
