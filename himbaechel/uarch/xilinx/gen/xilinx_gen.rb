require 'optparse'
require 'set'
require 'fileutils'
require_relative '../../../himbaechel_dbgen/chip'
require_relative 'xilinx_device'
require_relative 'filters'
require_relative 'parse_sdf'

def lookup_port_type(t)
  case t
  when "INPUT"  then PinType::INPUT
  when "OUTPUT" then PinType::OUTPUT
  when "BIDIR"  then PinType::INOUT
  else raise "unknown port type #{t}"
  end
end

def gen_bel_name(site, bel_name)
  prim_st = site.primary.site_type
  if ["IOB33M", "IOB33S", "IOB33", "IOB18M", "IOB18S", "IOB18"].include?(prim_st)
    "#{site.site_type}.#{bel_name}"
  else
    bel_name
  end
end

module PipClass
  TILE_ROUTING   = 0
  SITE_ENTRANCE  = 1
  SITE_EXIT      = 2
  SITE_INTERNAL  = 3
  LUT_PERMUTATION = 4
  LUT_ROUTETHRU  = 5
  CONST_DRIVER   = 6
end

class PipExtraData < BBAStruct
  attr_accessor :site_key, :bel_name, :pip_config
  def initialize(site_key: -1, bel_name: nil, pip_config: 0)
    @site_key = site_key
    @bel_name = bel_name || IdString.new(0)
    @pip_config = pip_config
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@site_key)
    bba.u32(@bel_name.index)
    bba.u32(@pip_config)
  end
end

class BelExtraData < BBAStruct
  attr_accessor :name_in_site
  def initialize(name_in_site:)
    @name_in_site = name_in_site
  end
  def serialise_lists(context, bba); end
  def serialise(context, bba)
    bba.u32(@name_in_site.index)
  end
end

class SiteInst < BBAStruct
  attr_accessor :name_prefix, :site_x, :site_y, :rel_x, :rel_y, :int_x, :int_y, :variants
  def initialize(name_prefix:, site_x:, site_y:, rel_x:, rel_y:, int_x:, int_y:, variants: [])
    @name_prefix = name_prefix
    @site_x = site_x; @site_y = site_y
    @rel_x = rel_x; @rel_y = rel_y
    @int_x = int_x; @int_y = int_y
    @variants = variants
  end
  def serialise_lists(context, bba)
    bba.label("#{context}_variants")
    @variants.each { |v| bba.u32(v.index) }
  end
  def serialise(context, bba)
    bba.u32(@name_prefix.index)
    bba.u16(@site_x); bba.u16(@site_y)
    bba.u16(@rel_x);  bba.u16(@rel_y)
    bba.u16(@int_x);  bba.u16(@int_y)
    bba.slice("#{context}_variants", @variants.length)
  end
end

class TileExtraData < BBAStruct
  attr_accessor :name_prefix, :tile_x, :tile_y, :sites
  def initialize(name_prefix, tile_x, tile_y)
    @name_prefix = name_prefix
    @tile_x = tile_x; @tile_y = tile_y
    @sites = []
  end
  def serialise_lists(context, bba)
    @sites.each_with_index { |site, i| site.serialise_lists("#{context}_si#{i}", bba) }
    bba.label("#{context}_sites")
    @sites.each_with_index { |site, i| site.serialise("#{context}_si#{i}", bba) }
  end
  def serialise(context, bba)
    bba.u32(@name_prefix.index)
    bba.u16(@tile_x); bba.u16(@tile_y)
    bba.slice("#{context}_sites", @sites.length)
  end
end

def timing_pip_class(pip)
  "#{pip.is_buffered ? 'buf' : 'sw'}_d#{pip.max_delay}_r#{pip.resistance}_c#{pip.capacitance}"
end

$seen_pip_timings = Set.new
$seen_node_timings = Set.new

def import_tiletype(ch, tile)
  tile_type = tile.tile_type
  if tile.x == 0 && tile.y == 0
    raise "expected NULL at (0,0), got #{tile_type}" unless tile_type == "NULL"
    tile_type = "NULL_CORNER"
  end
  tt = ch.create_tile_type(tile_type)

  # Import tile wires
  tile.wires.each do |wire|
    nw = tt.create_wire(wire.name, wire.intent)
    nw.flags = -1
    nw.const_value = ch.strs.id("GND") if wire.is_gnd
    nw.const_value = ch.strs.id("VCC") if wire.is_vcc
  end

  if tile_type == "NULL_CORNER"
    tt.create_wire("GND", "GND", "GND")
    tt.create_wire("VCC", "VCC", "VCC")

    gnd = tt.create_bel("PSEUDO_GND", "PSEUDO_GND", 0)
    gnd.site = -1
    gnd.extra_data = BelExtraData.new(name_in_site: ch.strs.id("PSEUDO_GND"))
    gnd.flags |= BEL_FLAG_GLOBAL
    tt.add_bel_pin(gnd, "Y", "GND", PinType::OUTPUT)

    vcc = tt.create_bel("PSEUDO_VCC", "PSEUDO_VCC", 1)
    vcc.site = -1
    vcc.extra_data = BelExtraData.new(name_in_site: ch.strs.id("PSEUDO_VCC"))
    vcc.flags |= BEL_FLAG_GLOBAL
    tt.add_bel_pin(vcc, "Y", "VCC", PinType::OUTPUT)
  end

  add_pip = lambda do |src_wire, dst_wire, pip_class: PipClass::TILE_ROUTING, timing: "",
                        site_key: -1, bel_name: "", pip_config: 0|
    np = tt.create_pip(src_wire, dst_wire, timing)
    np.flags = pip_class
    np.extra_data = PipExtraData.new(site_key: site_key, bel_name: ch.strs.id(bel_name), pip_config: pip_config)
  end

  lookup_site_wire = lambda do |sw|
    canon_name = "#{sw.site.rel_name}.#{sw.name}"
    unless tt.has_wire(canon_name)
      nw = tt.create_wire(canon_name, sw.name == "GND_WIRE" ? "INTENT_SITE_GND" : "INTENT_SITE_WIRE")
      nw.flags = sw.site.primary.index
    end
    canon_name
  end

  add_site_io_pip = lambda do |pin|
    pn = pin.name
    s = pin.site
    return nil if pin.tile_wire.nil?
    if ["OUTPUT", "BIDIR"].include?(pin.dir)
      return nil if s.primary.site_type == "IPAD" && pn == "O"
      add_pip.call(lookup_site_wire.call(pin.site_wire), pin.tile_wire.name,
        pip_class: PipClass::SITE_EXIT, timing: "SITE_NULL")
    else
      if ["SLICEL", "SLICEM"].include?(s.site_type)
        swn = pin.site_wire.name
        if swn.length == 2 && "ABCDEFGH".include?(swn[0]) && "123456".include?(swn[1])
          i = swn[1].to_i
          1.upto(6) do |j|
            next if (i == 6) != (j == 6)
            pip_config = ("ABCDEFGH".index(swn[0]) << 8) | ((j - 1) << 4) | (i - 1)
            pip_config |= (4 << 8) if s.rel_xy[0] == 1
            add_pip.call(s.pin("#{swn[0]}#{j}").tile_wire.name, lookup_site_wire.call(pin.site_wire),
              pip_class: PipClass::LUT_PERMUTATION,
              pip_config: pip_config,
              site_key: (s.index << 8),
              timing: "SITE_NULL")
          end
          return
        end
      end
      add_pip.call(pin.tile_wire.name, lookup_site_wire.call(pin.site_wire),
        pip_class: PipClass::SITE_ENTRANCE, timing: "SITE_NULL")
    end
  end

  tile.sites.each do |site|
    seen_pins = Set.new
    site.available_variants.each_with_index do |variant, variant_idx|
      next if variant == "FIFO36E1"
      sv = site.variant(variant)
      variant_key = (site.index << 8) | (variant_idx & 0xFF)
      sv.bels.each do |bel|
        z = get_bel_z_override(bel, tt.bels.length)
        next if z == -1
        bel_name = gen_bel_name(sv, bel.name)
        nb = tt.create_bel("#{site.rel_name}.#{bel_name}", get_bel_type_override(bel.bel_type), z)
        nb.site = variant_key
        nb.extra_data = BelExtraData.new(name_in_site: ch.strs.id(bel_name))
        nb.flags |= 2 if bel.bel_class == "RBEL"
        nb.flags |= BEL_FLAG_GLOBAL if is_global_bel(bel)
        bel.pins.each do |pin|
          tt.add_bel_pin(nb, pin.name, lookup_site_wire.call(pin.site_wire), lookup_port_type(pin.dir))
        end
      end
      sv.pins.each do |pin|
        pin_key = [pin.name, pin.site_wire.name]
        unless seen_pins.include?(pin_key)
          add_site_io_pip.call(pin)
          seen_pins.add(pin_key)
        end
      end
      sv.pips.each do |site_pip|
        next if site_pip.bel.bel_type.include?("LUT")
        bel_name = site_pip.bel.name
        bel_pin = site_pip.bel_input
        next if (bel_name == "ADI1MUX" && bel_pin == "BDI1") ||
                (bel_name == "BDI1MUX" && bel_pin == "DI") ||
                (bel_name == "CDI1MUX" && bel_pin == "DI") ||
                bel_name.start_with?("TFBUSED") ||
                bel_name == "OMUX" ||
                bel_name == "IDELMUXE3"
        add_pip.call(lookup_site_wire.call(site_pip.src_wire), lookup_site_wire.call(site_pip.dst_wire),
          pip_class: PipClass::SITE_INTERNAL,
          site_key: variant_key,
          bel_name: bel_name,
          pip_config: ch.strs.id(bel_pin).index,
          timing: "SITE_NULL")
      end
    end
  end

  tile.pips.each do |pip|
    next unless include_pip(tile.tile_type, pip)
    tcls = timing_pip_class(pip)
    unless $seen_pip_timings.include?(tcls)
      ch.timing.set_pip_class(
        grade: "DEFAULT", name: tcls,
        delay: TimingValue.new((pip.min_delay * 1000).to_i, (pip.max_delay * 1000).to_i),
        in_cap: TimingValue.new((pip.capacitance * 1000).to_i),
        out_res: TimingValue.new(pip.resistance.to_i),
        is_buffered: pip.is_buffered
      )
      $seen_pip_timings.add(tcls)
    end
    pip_cfg = pip.is_route_thru ? 1 : 0
    add_pip.call(pip.src_wire.name, pip.dst_wire.name,
      pip_class: PipClass::TILE_ROUTING, timing: tcls, pip_config: pip_cfg)
    if pip.is_bidi
      add_pip.call(pip.dst_wire.name, pip.src_wire.name,
        pip_class: PipClass::TILE_ROUTING, timing: tcls, pip_config: pip_cfg)
    end
  end
end

def import_sdf_timings(variant, sdfcell)
  sdfcell.entries.each do |entry|
    if entry.is_a?(IOPath)
      variant.add_comb_arc(entry.from_pin, entry.to_pin,
        TimingValue.new(
          (([entry.rising.minv, entry.falling.minv].min) * 1000).to_i,
          (([entry.rising.maxv, entry.falling.maxv].max) * 1000).to_i
        ))
    end
  end
end

def import_bram_timings(timing, sdf)
  import_bus_sethold = lambda do |cell, port, width, clock, entry|
    width.times do |i|
      cell.add_setup_hold(clock, "#{port}#{i}", ClockEdge::RISING,
        TimingValue.new((entry.setup.minv * 1000).to_i, (entry.setup.maxv * 1000).to_i),
        TimingValue.new((entry.hold.minv  * 1000).to_i, (entry.hold.maxv  * 1000).to_i))
    end
  end

  import_bus_clkq = lambda do |cell, port, width, clock, entry|
    width.times do |i|
      cell.add_clock_out(clock, "#{port}#{i}", ClockEdge::RISING,
        TimingValue.new(
          ([entry.rising.minv, entry.falling.minv].min * 1000).to_i,
          ([entry.rising.maxv, entry.falling.maxv].max * 1000).to_i
        ))
    end
  end

  import_pin_sethold = lambda do |cell, port, clock, entry|
    cell.add_setup_hold(clock, port, ClockEdge::RISING,
      TimingValue.new((entry.setup.minv * 1000).to_i, (entry.setup.maxv * 1000).to_i),
      TimingValue.new((entry.hold.minv  * 1000).to_i, (entry.hold.maxv  * 1000).to_i))
  end

  [[false, false], [false, true], [true, false], [true, true]].each do |wsdp, rsdp|
    bram18 = timing.add_cell_variant("DEFAULT",
      "RAMB18E1_RAMB18E1_#{wsdp ? 'WSDP' : 'WTDP'}_#{rsdp ? 'RSDP' : 'RTDP'}")

    sdf.cells[["RAMBFIFO36E1", "RAMBFIFO36E1"]].entries.each do |entry|
      next unless entry.is_a?(SetupHoldCheck)
      import_bus_sethold.call(bram18, "ADDRARDADDR", 14, "CLKARDCLK", entry) if entry.pin == "ADDRAU"
      import_bus_sethold.call(bram18, "ADDRBWRADDR", 14, "CLKBWRCLK", entry) if entry.pin == "ADDRBU"
      import_bus_sethold.call(bram18, "WEA",  4, "CLKARDCLK", entry) if entry.pin == "WEAU"
      import_bus_sethold.call(bram18, "WEBWE", 8, "CLKBWRCLK", entry) if entry.pin == "WEBU"
    end
    sdf.cells[["RAMBFIFO36E1_ISFIFO_FALSE", "RAMBFIFO36E1"]].entries.each do |entry|
      next unless entry.is_a?(SetupHoldCheck)
      import_pin_sethold.call(bram18, "ENARDEN",      "CLKARDCLK", entry) if entry.pin == "ENARDENU"
      import_pin_sethold.call(bram18, "ENBWREN",      "CLKBWRCLK", entry) if entry.pin == "ENBWRENU"
      import_pin_sethold.call(bram18, "RSTRAMARSTRAM","CLKARDCLK", entry) if entry.pin == "RSTRAMAU"
      import_pin_sethold.call(bram18, "RSTRAMB",      "CLKBWRCLK", entry) if entry.pin == "RSTRAMBU"
    end
    tdp_key = "RAMBFIFO36E1RAM_MODE_RAMB18TDP_U_WRITE_MODE_U_NC_EN_ECC_READ_FALSE_EN_ECC_WRITE_FALSE"
    sdf.cells[[tdp_key, "RAMBFIFO36E1"]].entries.each do |entry|
      next unless entry.is_a?(SetupHoldCheck)
      import_bus_sethold.call(bram18, "DIADI",   16, wsdp ? "CLKBWRCLK" : "CLKARDCLK", entry) if entry.pin == "DIADIU"
      import_bus_sethold.call(bram18, "DIBDI",   16, "CLKBWRCLK", entry) if entry.pin == "DIBDIU"
      import_bus_sethold.call(bram18, "DIPADIP",  2, wsdp ? "CLKBWRCLK" : "CLKARDCLK", entry) if entry.pin == "DIPADIPU"
      import_bus_sethold.call(bram18, "DIPBDIP",  2, "CLKBWRCLK", entry) if entry.pin == "DIPBDIPU"
    end
    sdp_doa_key = "RAMBFIFO36E1RAM_MODE_U_RAMB18SDP_U_DOA_REG_U_0_EN_ECC_READ_FALSE"
    sdf.cells[[sdp_doa_key, "RAMBFIFO36E1"]].entries.each do |entry|
      next unless entry.is_a?(IOPath)
      import_bus_clkq.call(bram18, "DOADO",  16, "CLKARDCLK", entry) if entry.to_pin == "DOADOU"
      import_bus_clkq.call(bram18, "DOPADOP", 2, "CLKARDCLK", entry) if entry.to_pin == "DOPADOPU"
    end
    tdp_dob_key = "RAMBFIFO36E1RAM_MODE_U_RAMB18TDP_U_DOB_REG_U_0_EN_ECC_READ_FALSE"
    sdf.cells[[tdp_dob_key, "RAMBFIFO36E1"]].entries.each do |entry|
      next unless entry.is_a?(IOPath)
      import_bus_clkq.call(bram18, "DOBDO",  16, rsdp ? "CLKARDCLK" : "CLKBWRCLK", entry) if entry.to_pin == "DOBDOU"
      import_bus_clkq.call(bram18, "DOPBDOP", 2, rsdp ? "CLKARDCLK" : "CLKBWRCLK", entry) if entry.to_pin == "DOPBDOPU"
    end

    bram36 = timing.add_cell_variant("DEFAULT",
      "RAMB36E1_RAMB36E1_#{wsdp ? 'WSDP' : 'WTDP'}_#{rsdp ? 'RSDP' : 'RTDP'}")

    ["L", "U"].each do |u|
      sdf.cells[["RAMBFIFO36E1", "RAMBFIFO36E1"]].entries.each do |entry|
        next unless entry.is_a?(SetupHoldCheck)
        import_bus_sethold.call(bram36, "ADDRARDADDR#{u}", u == "L" ? 15 : 14, "CLKARDCLK", entry) if entry.pin == "ADDRAU"
        import_bus_sethold.call(bram36, "ADDRBWRADDR#{u}", u == "L" ? 15 : 14, "CLKBWRCLK", entry) if entry.pin == "ADDRBU"
        import_bus_sethold.call(bram36, "WEA#{u}",   4, "CLKARDCLK#{u}", entry) if entry.pin == "WEAU"
        import_bus_sethold.call(bram36, "WEBWE#{u}", 8, "CLKBWRCLK#{u}", entry) if entry.pin == "WEBU"
      end
      sdf.cells[["RAMBFIFO36E1_ISFIFO_FALSE", "RAMBFIFO36E1"]].entries.each do |entry|
        next unless entry.is_a?(SetupHoldCheck)
        import_pin_sethold.call(bram36, "ENARDEN#{u}",       "CLKARDCLK#{u}", entry) if entry.pin == "ENARDENU"
        import_pin_sethold.call(bram36, "ENBWREN#{u}",       "CLKBWRCLK#{u}", entry) if entry.pin == "ENBWRENU"
        import_pin_sethold.call(bram36, "RSTRAMARSTRAM#{u}", "CLKARDCLK#{u}", entry) if entry.pin == "RSTRAMAU"
        import_pin_sethold.call(bram36, "RSTRAMB#{u}",       "CLKBWRCLK#{u}", entry) if entry.pin == "RSTRAMBU"
      end
    end
    sdf.cells[[tdp_key, "RAMBFIFO36E1"]].entries.each do |entry|
      next unless entry.is_a?(SetupHoldCheck)
      import_bus_sethold.call(bram36, "DIADI",   32, wsdp ? "CLKBWRCLK" : "CLKARDCLK", entry) if entry.pin == "DIADIU"
      import_bus_sethold.call(bram36, "DIBDI",   32, "CLKBWRCLK", entry) if entry.pin == "DIBDIU"
      import_bus_sethold.call(bram36, "DIPADIP",  4, wsdp ? "CLKBWRCLK" : "CLKARDCLK", entry) if entry.pin == "DIPADIPU"
      import_bus_sethold.call(bram36, "DIPBDIP",  4, "CLKBWRCLK", entry) if entry.pin == "DIPBDIPU"
    end
    sdf.cells[[sdp_doa_key, "RAMBFIFO36E1"]].entries.each do |entry|
      next unless entry.is_a?(IOPath)
      import_bus_clkq.call(bram36, "DOADO",  32, "CLKARDCLK", entry) if entry.to_pin == "DOADOU"
      import_bus_clkq.call(bram36, "DOPADOP", 4, "CLKARDCLK", entry) if entry.to_pin == "DOPADOPU"
    end
    sdf.cells[[tdp_dob_key, "RAMBFIFO36E1"]].entries.each do |entry|
      next unless entry.is_a?(IOPath)
      import_bus_clkq.call(bram36, "DOBDO",  32, rsdp ? "CLKARDCLK" : "CLKBWRCLK", entry) if entry.to_pin == "DOBDOU"
      import_bus_clkq.call(bram36, "DOPBDOP", 4, rsdp ? "CLKARDCLK" : "CLKBWRCLK", entry) if entry.to_pin == "DOPBDOPU"
    end
  end
end

def main
  xlbase = File.expand_path("..", File.dirname(File.realpath(__FILE__)))

  options = {
    metadata: File.join(xlbase, "meta", "artix7"),
    constids: File.join(xlbase, "constids.inc")
  }
  OptionParser.new do |opts|
    opts.on("--xray XRAY",       "Project X-Ray device database path") { |v| options[:xray] = v }
    opts.on("--metadata META",   "nextpnr-xilinx site metadata root")  { |v| options[:metadata] = v }
    opts.on("--device DEVICE",   "name of device to export")           { |v| options[:device] = v }
    opts.on("--constids FILE",   "nextpnr constids file to read")      { |v| options[:constids] = v }
    opts.on("--bba BBA",         "bba file to write")                  { |v| options[:bba] = v }
  end.parse!

  raise "Missing --xray"   unless options[:xray]
  raise "Missing --device" unless options[:device]
  raise "Missing --bba"    unless options[:bba]

  metadata_root = options[:metadata]
  xraydb_root   = options[:xray]
  device        = options[:device]

  if device.include?("xc7z")
    metadata_root = metadata_root.sub("artix7", "zynq7")
    xraydb_root   = xraydb_root.sub("artix7", "zynq7")
  end
  if device.include?("xc7k")
    metadata_root = metadata_root.sub("artix7", "kintex7")
    xraydb_root   = xraydb_root.sub("artix7", "kintex7")
  end
  if device.include?("xc7s")
    metadata_root = metadata_root.sub("artix7", "spartan7")
    xraydb_root   = xraydb_root.sub("artix7", "spartan7")
  end

  d = import_device(device, xraydb_root, metadata_root)
  ch = Chip.new("xilinx", device, d.width, d.height)
  ch.strs.read_constids(File.join(File.dirname(__FILE__), options[:constids]))
  ch.set_speed_grades(["DEFAULT"])

  d.tiles.each do |tile|
    tile_type = tile.tile_type
    if tile.x == 0 && tile.y == 0
      raise "expected NULL at (0,0)" unless tile_type == "NULL"
      tile_type = "NULL_CORNER"
    end
    import_tiletype(ch, tile) unless ch.tile_type_idx.key?(tile_type)
    ti = ch.set_tile_type(tile.x, tile.y, tile_type)
    prefix, tx, ty = tile.split_name
    ti.extra_data = TileExtraData.new(ch.strs.id(prefix), tx, ty)
    tile.sites.each do |site|
      ti.extra_data.sites << SiteInst.new(
        name_prefix: ch.strs.id(site.prefix),
        site_x: site.grid_xy[0], site_y: site.grid_xy[1],
        rel_x: site.rel_xy[0],   rel_y: site.rel_xy[1],
        int_x: tile.interconn_xy[0], int_y: tile.interconn_xy[1],
        variants: site.available_variants.map { |v| ch.strs.id(v) }
      )
    end
  end

  seen_nodes    = Set.new
  tt_used_wires = {}
  puts "Processing nodes..."
  d.height.times do |row|
    d.width.times do |col|
      t = d.tiles_by_xy[[col, row]]
      t.wires.each do |w|
        n = w.node
        uid = n.unique_index
        next if seen_nodes.include?(uid)
        if n.wires.length > 1
          node_wires = []
          node_cap = 0
          node_res = 0
          2.times do |j|
            n.wires.each do |nw|
              is_int = ["INT", "INT_L", "INT_R"].include?(nw.tile.tile_type)
              next if is_int != (j == 0)
              tt_used_wires[nw.tile.tile_type] ||= nw.tile.used_wire_indices
              node_cap += (nw.capacitance * 1000).to_i
              node_res += nw.resistance.to_i
              next unless tt_used_wires[nw.tile.tile_type].include?(nw.index)
              node_wires << NodeWire.new(nw.tile.x, nw.tile.y, nw.index)
            end
          end
          if node_wires.length > 1
            timing_class = "node_c#{node_cap}_c#{node_res}"
            ch.add_node(node_wires, timing_class: timing_class)
            unless $seen_node_timings.include?(timing_class)
              ch.timing.set_node_class(grade: "DEFAULT", name: timing_class,
                delay: TimingValue.new(0),
                cap: TimingValue.new(node_cap),
                res: TimingValue.new(node_res))
              $seen_node_timings.add(timing_class)
            end
          end
          node_wires = nil
        end
        seen_nodes.add(uid)
      end
    end
  end

  ch.timing.set_pip_class(grade: "DEFAULT", name: "SITE_NULL", delay: TimingValue.new(20))

  lut = ch.timing.add_cell_variant("DEFAULT", "SLICE_LUTX")
  1.upto(6) do |i|
    lut.add_comb_arc("A#{i}", "O6", TimingValue.new(100, 125))
    lut.add_comb_arc("A#{i}", "O5", TimingValue.new(120, 150)) if i <= 5
  end
  1.upto(8) { |i| lut.add_setup_hold("CLK", "WA#{i}", ClockEdge::RISING, TimingValue.new(100, 500), TimingValue.new(100, 200)) }
  lut.add_setup_hold("CLK", "WE",  ClockEdge::RISING, TimingValue.new(100, 600), TimingValue.new(100, 100))
  lut.add_setup_hold("CLK", "DI1", ClockEdge::RISING, TimingValue.new(100, 100), TimingValue.new(100, 100))

  ff = ch.timing.add_cell_variant("DEFAULT", "SLICE_FFX")
  ff.add_setup_hold("CK", "CE", ClockEdge::RISING, TimingValue.new(100, 100), TimingValue.new(0, 0))
  ff.add_setup_hold("CK", "SR", ClockEdge::RISING, TimingValue.new(100, 100), TimingValue.new(0, 0))
  ff.add_setup_hold("CK", "D",  ClockEdge::RISING, TimingValue.new(100, 100), TimingValue.new(200, 200))
  ff.add_clock_out("CK", "Q", ClockEdge::RISING, TimingValue.new(300, 350))

  timings_root = xraydb_root
  timings_root = timings_root.sub("kintex7", "artix7") if xraydb_root.include?("kintex7")
  slicem_sdf = parse_sdf_file(File.join(timings_root, "timings", "slicem.sdf"))
  mux = ch.timing.add_cell_variant("DEFAULT", "SELMUX2_1")
  import_sdf_timings(mux, slicem_sdf.cells[["SELMUX2_1", "SLICEM/F7BMUX"]])
  carry = ch.timing.add_cell_variant("DEFAULT", "CARRY4")
  import_sdf_timings(carry, slicem_sdf.cells[["CARRY4", "SLICEM"]])

  import_bram_timings(ch.timing, parse_sdf_file(File.join(timings_root, "timings", "BRAM_L.sdf")))

  d.packages.sort.each do |package_name, package|
    pkg = ch.create_package(package_name)
    package.pin_map.sort.each do |pin, site|
      site_data = d.sites_by_name[site]
      bel_name = gen_bel_name(site_data, "PAD")
      ch.tile_type_at(site_data.tile.x, site_data.tile.y)
      pkg.create_pad(pin, "X#{site_data.tile.x}Y#{site_data.tile.y}",
        "#{site_data.rel_name}.#{bel_name}", "", 0)
    end
  end

  ch.write_bba(options[:bba])
end

main if __FILE__ == $PROGRAM_NAME
