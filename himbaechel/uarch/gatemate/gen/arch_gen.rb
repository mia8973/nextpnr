#
#  nextpnr -- Next Generation Place and Route
#
#  Copyright (C) 2024  The Project Peppercorn Authors.
#
#  Permission to use, copy, modify, and/or distribute this software for any
#  purpose with or without fee is hereby granted, provided that the above
#  copyright notice and this permission notice appear in all copies.
#
#  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
#  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
#  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
#  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
#  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
#  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

require 'optparse'
require 'set'
require_relative '../../../himbaechel_dbgen/chip'

PIP_EXTRA_MUX = 1

MUX_INVERT  = 1
MUX_VISIBLE = 2
MUX_CONFIG  = 4
MUX_ROUTING = 8

options = {}
OptionParser.new do |opts|
  opts.on("--lib LIB", "Project Peppercorn ruby database script path") { |v| options[:lib] = v }
  opts.on("--device DEVICE", "name of device to export") { |v| options[:device] = v }
  opts.on("--bba BBA", "bba file to write") { |v| options[:bba] = v }
end.parse!

raise "Missing --lib" unless options[:lib]
raise "Missing --device" unless options[:device]
raise "Missing --bba" unless options[:bba]

$LOAD_PATH << File.expand_path(options[:lib])
require 'chip'
require 'die'

pip_tmg_names = Set.new

class TileExtraData < BBAStruct
  attr_accessor :die, :bit_x, :bit_y, :tile_x, :tile_y, :prim_id
  def initialize(die: 0, bit_x: 0, bit_y: 0, tile_x: 0, tile_y: 0, prim_id: 0)
    @die = die; @bit_x = bit_x; @bit_y = bit_y
    @tile_x = tile_x; @tile_y = tile_y; @prim_id = prim_id
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u8(@die); bba.u8(@bit_x); bba.u8(@bit_y)
    bba.u8(@tile_x); bba.u8(@tile_y); bba.u8(@prim_id)
    bba.u16(0)
  end
end

class PipExtraData < BBAStruct
  attr_accessor :pip_type, :name, :bits, :value, :invert, :plane, :block, :resource, :group_index
  def initialize(pip_type:, name:, bits: 0, value: 0, invert: 0, plane: 0, block: 0, resource: 0, group_index: 0)
    @pip_type = pip_type; @name = name; @bits = bits; @value = value
    @invert = invert; @plane = plane; @block = block; @resource = resource
    @group_index = group_index
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@name.index); bba.u8(@bits); bba.u8(@value)
    bba.u8(@invert); bba.u8(@pip_type); bba.u8(@plane); bba.u8(0); bba.u16(0)
    bba.u32(@block); bba.u32(@resource); bba.u32(@group_index)
  end
end

class BelPinConstraint < BBAStruct
  attr_accessor :index, :pin_name, :constr_x, :constr_y, :constr_z
  def initialize(index:, pin_name:, constr_x: 0, constr_y: 0, constr_z: 0)
    @index = index; @pin_name = pin_name
    @constr_x = constr_x; @constr_y = constr_y; @constr_z = constr_z
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@pin_name.index)
    bba.u16(@constr_x); bba.u16(@constr_y); bba.u16(@constr_z); bba.u16(0)
  end
end

class BelExtraData < BBAStruct
  attr_accessor :constraints
  def initialize; @constraints = []; end
  def add_constraints(pin, x, y, z)
    @constraints << BelPinConstraint.new(index: @constraints.length, pin_name: pin, constr_x: x, constr_y: y, constr_z: z)
  end
  def serialise_lists(context, bba)
    @constraints.sort_by! { |p| p.pin_name.index }
    bba.label("#{context}_constraints")
    @constraints.each_with_index { |t, i| t.serialise("#{context}_constraint#{i}", bba) }
  end
  def serialise(context, bba)
    bba.slice("#{context}_constraints", @constraints.length)
  end
end

class PadExtraData < BBAStruct
  attr_accessor :x, :y, :z
  def initialize(x: 0, y: 0, z: 0); @x = x; @y = y; @z = z; end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u16(@x); bba.u16(@y); bba.u16(@z); bba.u16(0)
  end
end

class TimingExtraData < BBAStruct
  attr_accessor :name, :delay
  def initialize(name:, delay: TimingValue.new)
    @name = name; @delay = delay
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@name.index)
    @delay.serialise(context, bba)
  end
end

class SpeedGradeExtraData < BBAStruct
  attr_accessor :timings
  def initialize; @timings = []; end
  def add_timing(name:, delay:)
    @timings << TimingExtraData.new(name: name, delay: delay)
  end
  def serialise_lists(context, bba)
    bba.label("#{context}_timings")
    @timings.each_with_index { |t, i| t.serialise("#{context}_timing#{i}", bba) }
  end
  def serialise(context, bba)
    bba.slice("#{context}_timings", @timings.length)
  end
end

class DieRegion < BBAStruct
  attr_accessor :name, :x1, :y1, :x2, :y2
  def initialize(name:, x1: 0, y1: 0, x2: 0, y2: 0)
    @name = name; @x1 = x1; @y1 = y1; @x2 = x2; @y2 = y2
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@name.index)
    bba.u16(@x1); bba.u16(@y1); bba.u16(@x2); bba.u16(@y2)
  end
end

class ChipExtraData < BBAStruct
  attr_accessor :dies
  def initialize; @dies = []; end
  def add_die(name, x1, y1, x2, y2)
    @dies << DieRegion.new(name: name, x1: x1, y1: y1, x2: x2, y2: y2)
  end
  def serialise_lists(context, bba)
    @dies.sort_by! { |p| p.name.index }
    bba.label("#{context}_dies")
    @dies.each_with_index { |t, i| t.serialise("#{context}_die#{i}", bba) }
  end
  def serialise(context, bba)
    bba.slice("#{context}_dies", @dies.length)
  end
end

def convert_timing(tim)
  TimingValue.new(tim.rise.min, tim.rise.max, tim.fall.min, tim.fall.max)
end

def set_timings(ch, pip_tmg_names)
  speed_grades = ["best_lpr", "best_eco", "best_spd",
                  "typ_lpr", "typ_eco", "typ_spd",
                  "worst_lpr", "worst_eco", "worst_spd"]
  rename_table = {
    "CINX_OUT1" => "_ARBLUT_CINX_OUT1",
    "CINX_OUT2" => "_ARBLUT_CINX_OUT2",
    "PINX_OUT1" => "_ARBLUT_PINX_OUT1",
    "PINX_OUT2" => "_ARBLUT_PINX_OUT2",
    "PINY1_OUT1" => "_ARBLUT_PINY1_OUT1",
    "PINY1_OUT2" => "_ARBLUT_PINY1_OUT2",
  }
  tmg = ch.set_speed_grades(speed_grades)
  speed_grades.each do |speed|
    puts "Loading timings for #{speed}..."
    timing = Chip.get_timings(speed).sort.to_h
    tmg.get_speed_grade(speed).extra_data = SpeedGradeExtraData.new
    timing.each do |name, val|
      next if name.start_with?("sb_del_t", "im_x", "om_x", "sb_rim_xy", "edge_xy")
      name = "timing_" + (rename_table[name] || name).gsub(/[-= >]/, "_")
      tmg.get_speed_grade(speed).extra_data.add_timing(name: ch.strs.id(name), delay: convert_timing(val))
    end
    pip_tmg_names.each do |k|
      raise "pip class #{k} not found in timing data" unless timing.key?(k)
      tmg.set_pip_class(grade: speed, name: k, delay: convert_timing(timing[k]))
    end
  end
end

EXPECTED_VERSION = 1.13

RESOURCE_NAMES = {
  1 << 0  => "C_SELX",
  1 << 1  => "C_SELY1",
  1 << 2  => "C_SELY2",
  1 << 3  => "C_SEL_C",
  1 << 4  => "C_SEL_P",
  1 << 5  => "C_Y12",
  1 << 6  => "C_CX_I",
  1 << 7  => "C_CY1_I",
  1 << 8  => "C_CY2_I",
  1 << 9  => "C_PX_I",
  1 << 10 => "C_PY1_I",
  1 << 11 => "C_PY2_I",
}

def main(options, pip_tmg_names)
  # Range needs to be +1, but we are adding +2 more to coordinates, since
  # they are starting from -2 instead of zero required for nextpnr
  dev = Chip.get_device(options[:device])
  ch = Chip.new("gatemate", options[:device], dev.max_col + 3, dev.max_row + 3)
  # Init constant ids
  ch.strs.read_constids(File.join(File.dirname(__FILE__), "..", "constids.inc"))
  ch.read_gfxids(File.join(File.dirname(__FILE__), "..", "gfxids.inc"))

  begin
    if Chip.get_version != EXPECTED_VERSION
      puts "=============================================================================="
      puts "ERROR: Expected v#{EXPECTED_VERSION} and current v#{Chip.get_version} chip database mismatch"
      puts "       Please update prjpeppercorn and/or nextpnr"
      puts "=============================================================================="
      exit(-1)
    end
  rescue NoMethodError
    puts "=============================================================================="
    puts "ERROR: Unable to determine prjpepercorn version"
    puts "       Please update prjpeppercorn and/or nextpnr"
    puts "=============================================================================="
    exit(-1)
  end

  unless Chip.check_dly_available
    puts "=============================================================================="
    puts "ERROR: Delay files not, found"
    puts "       Run delay.sh in prjpeppercorn to download needed files"
    puts "=============================================================================="
    exit(-1)
  end

  ch.extra_data = ChipExtraData.new
  dev.dies.keys.sort.each do |d|
    ch.extra_data.add_die(
      ch.strs.id(dev.dies[d].name),
      dev.dies[d].offset_x, dev.dies[d].offset_y,
      dev.dies[d].offset_x + Die.num_cols - 1,
      dev.dies[d].offset_y + Die.num_rows - 1
    )
  end

  new_wires = {}
  wire_delay = {}
  dev.get_connections.each do |_, nodes|
    nodes.each do |conn|
      if conn.endpoint
        t_name = dev.get_tile_type(conn.x, conn.y)
        new_wires[t_name] ||= Set.new
        new_wires[t_name].add(conn.name)
        if wire_delay.key?(conn.name)
          raise "conflict delay #{conn.name}" unless wire_delay[conn.name] == conn.delay
        end
        wire_delay[conn.name] = conn.delay
      end
    end
  end

  Die.get_tile_type_list.sort.each do |type_name|
    tt = ch.create_tile_type(type_name)
    Die.get_groups_for_type(type_name).sort.each { |group| tt.create_group(group.name, group.type) }
    if type_name.include?("CPE")
      RESOURCE_NAMES.values.each { |name| tt.create_group(name, "RESOURCE") }
    end
    Die.get_endpoints_for_type(type_name).sort.each { |wire| tt.create_wire(wire.name, wire.type) }
    if new_wires.key?(type_name)
      new_wires[type_name].sort.each { |wire| tt.create_wire("#{wire}_n", "NODE_WIRE") }
    end
    Die.get_primitives_for_type(type_name).sort.each do |prim|
      bel = tt.create_bel(prim.name, prim.type, prim.z)
      bel.flags |= BEL_FLAG_HIDDEN if ["CPE_LT_FULL", "CPE_BRIDGE"].include?(prim.name)
      extra = BelExtraData.new
      Die.get_pins_constraint(type_name, prim.name, prim.type).sort.each do |constr|
        extra.add_constraints(ch.strs.id(constr.name), constr.rel_x, constr.rel_y, constr.pin_num == 2 ? 4 : 5)
      end
      bel.extra_data = extra
      Die.get_primitive_pins(prim.type).sort.each do |pin|
        tt.add_bel_pin(bel, pin.name, Die.get_pin_connection_name(prim, pin), pin.dir)
      end
    end
    Die.get_mux_connections_for_type(type_name).sort.each do |mux|
      pip_tmg_names.add(mux.delay) if mux.delay.length > 0
      pp = tt.create_pip(mux.src, mux.dst, mux.delay)
      if mux.name
        mux_flags = mux.invert ? MUX_INVERT : 0
        mux_flags |= MUX_VISIBLE if mux.visible
        mux_flags |= MUX_CONFIG if mux.config
        plane = 0
        plane = mux.name[4, 2].to_i if mux.name.start_with?("IM")
        plane = mux.name[8, 2].to_i if mux.name.start_with?("SB_SML") || mux.name.start_with?("SB_BIG")
        plane = mux.name[10, 2].to_i if mux.name.start_with?("SB_DRIVE")
        mux_flags |= MUX_ROUTING if mux.name == "CPE.C_SN"
        group_index = 0
        if mux.resource > 0
          group = RESOURCE_NAMES.fetch(mux.resource, "UNKNOWN")
          group_index = tt._group2idx[tt.strs.id(group)]
          tt.add_pip_to_group(pp, group)
        end
        pp.extra_data = PipExtraData.new(
          pip_type: PIP_EXTRA_MUX, name: ch.strs.id(mux.name),
          bits: mux.bits, value: mux.value, invert: mux_flags,
          plane: plane, block: mux.block, resource: mux.resource,
          group_index: group_index
        )
      end
    end
    if new_wires.key?(type_name)
      new_wires[type_name].sort.each do |wire|
        delay = wire_delay[wire]
        pip_tmg_names.add(delay) if delay.length > 0
        pp = tt.create_pip("#{wire}_n", wire, delay)
        plane = 0
        plane = wire[4, 2].to_i if wire.start_with?("IM")
        plane = wire[8, 2].to_i if wire.start_with?("SB_SML") || wire.start_with?("SB_BIG")
        plane = wire[10, 2].to_i if wire.start_with?("SB_DRIVE")
        pp.extra_data = PipExtraData.new(pip_type: PIP_EXTRA_MUX, name: ch.strs.id(""), plane: plane)
      end
    end
  end

  # Setup tile grid
  (dev.max_col + 3).times do |x|
    (dev.max_row + 3).times do |y|
      ti = ch.set_tile_type(x, y, dev.get_tile_type(x - 2, y - 2))
      tileinfo = dev.get_tile_info(x - 2, y - 2)
      ti.extra_data = TileExtraData.new(
        die: tileinfo.die, bit_x: tileinfo.bit_x, bit_y: tileinfo.bit_y,
        tile_x: tileinfo.tile_x, tile_y: tileinfo.tile_y, prim_id: tileinfo.prim_index
      )
    end
  end

  # Create nodes between tiles
  dev.get_connections.each do |_, nodes|
    node = nodes.sort.map do |conn|
      NodeWire.new(conn.x + 2, conn.y + 2, conn.endpoint ? "#{conn.name}_n" : conn.name)
    end
    ch.add_node(node)
  end
  set_timings(ch, pip_tmg_names)

  dev.get_packages.each do |package|
    pkg = ch.create_package(package)
    dev.get_package_pads(package).sort.each do |pad|
      pp = pkg.create_pad(pad.name, "X#{pad.x + 2}Y#{pad.y + 2}", pad.bel, pad.function, pad.bank, pad.flags)
      pp.extra_data = PadExtraData.new(x: pad.ddr.x + 2, y: pad.ddr.y + 2, z: pad.ddr.z == 0 ? 4 : 5)
    end
  end

  ch.write_bba(options[:bba])
end

main(options, pip_tmg_names)
