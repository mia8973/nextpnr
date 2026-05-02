#!/usr/bin/env ruby
require 'optparse'
require 'json'
require 'set'

location_types = {}
type_at_location = {}
tiletype_names = {}
gfx_wire_ids = {}
gfx_wire_names = []

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: trellis_import.rb [options] device"
  opts.on("-p", "--constids PATH", "path to constids.inc") { |v| options[:constids] = v }
  opts.on("-g", "--gfxh PATH", "path to gfx.h") { |v| options[:gfxh] = v }
  opts.on("-L", "--libdir PATH", "extra Ruby library path") do |v|
    options[:libdir] ||= []
    options[:libdir] << v
  end
end.parse!

device_arg = ARGV.shift
if device_arg.nil?
  $stderr.puts "Error: device argument required"
  exit(1)
end

if options[:libdir]
  options[:libdir].each { |d| $LOAD_PATH.unshift(d) }
end

require 'pytrellis'
require 'database'
require 'pip_classes'
require 'timing_dbs'

File.open(options[:gfxh]) do |f|
  state = 0
  f.each_line do |line|
    if state == 0 && line.start_with?("enum GfxTileWireId")
      state = 1
    elsif state == 1 && line.start_with?("};")
      state = 0
    elsif state == 1 && (line.start_with?("{") || line.strip == "")
      # pass
    elsif state == 1
      idx = gfx_wire_ids.length
      name = line.strip.sub(/,$/, "")
      gfx_wire_ids[name] = idx
      gfx_wire_names << name
    end
  end
end

def gfx_wire_alias(gfx_wire_ids, old_name, new_name)
  raise "#{old_name} not in gfx_wire_ids" unless gfx_wire_ids.include?(old_name)
  raise "#{new_name} already in gfx_wire_ids" if gfx_wire_ids.include?(new_name)
  gfx_wire_ids[new_name] = gfx_wire_ids[old_name]
end

def wire_type(name)
  parts = name.split('/')

  if parts[0].start_with?("X") && parts[1].start_with?("Y")
    parts = parts[2..]
  end

  return "WIRE_TYPE_SLICE"      if parts[0].end_with?("_SLICE")
  return "WIRE_TYPE_DQS"        if parts[0].end_with?("_DQS")
  return "WIRE_TYPE_IOLOGIC"    if parts[0].end_with?("_IOLOGIC")
  return "WIRE_TYPE_SIOLOGIC"   if parts[0].end_with?("_SIOLOGIC")
  return "WIRE_TYPE_PIO"        if parts[0].end_with?("_PIO")
  return "WIRE_TYPE_DDRDLL"     if parts[0].end_with?("_DDRDLL")
  return "WIRE_TYPE_CCLK"       if parts[0].end_with?("_CCLK")
  return "WIRE_TYPE_EXTREF"     if parts[0].end_with?("_EXTREF")
  return "WIRE_TYPE_DCU"        if parts[0].end_with?("_DCU")
  return "WIRE_TYPE_EBR"        if parts[0].end_with?("_EBR")
  return "WIRE_TYPE_MULT18"     if parts[0].end_with?("_MULT18")
  return "WIRE_TYPE_ALU54"      if parts[0].end_with?("_ALU54")
  return "WIRE_TYPE_PLL"        if parts[0].end_with?("_PLL")
  return "WIRE_TYPE_SED"        if parts[0].end_with?("_SED")
  return "WIRE_TYPE_OSC"        if parts[0].end_with?("_OSC")
  return "WIRE_TYPE_JTAG"       if parts[0].end_with?("_JTAG")
  return "WIRE_TYPE_GSR"        if parts[0].end_with?("_GSR")
  return "WIRE_TYPE_DTR"        if parts[0].end_with?("_DTR")
  return "WIRE_TYPE_PCSCLKDIV"  if parts[0].end_with?("_PCSCLKDIV0")
  return "WIRE_TYPE_PCSCLKDIV"  if parts[0].end_with?("_PCSCLKDIV1")

  return "WIRE_TYPE_H00"   if parts[0].start_with?("H00")
  return "WIRE_TYPE_H01"   if parts[0].start_with?("H01")
  return "WIRE_TYPE_H01"   if parts[0].start_with?("HFI")
  return "WIRE_TYPE_H01"   if parts[0].start_with?("HL7")
  return "WIRE_TYPE_H02"   if parts[0].start_with?("H02")
  return "WIRE_TYPE_H06"   if parts[0].start_with?("H06")

  return "WIRE_TYPE_V00"   if parts[0].start_with?("V00")
  return "WIRE_TYPE_V01"   if parts[0].start_with?("V01")
  return "WIRE_TYPE_V02"   if parts[0].start_with?("V02")
  return "WIRE_TYPE_V06"   if parts[0].start_with?("V06")

  return "WIRE_TYPE_G_HPBX" if parts[0].start_with?("G_HPBX")
  return "WIRE_TYPE_G_VPTX" if parts[0].start_with?("G_VPTX")
  return "WIRE_TYPE_L_HPBX" if parts[0].start_with?("L_HPBX")
  return "WIRE_TYPE_R_HPBX" if parts[0].start_with?("R_HPBX")

  "WIRE_TYPE_NONE"
end

def is_global(loc)
  loc.x == -2 && loc.y == -2
end

def get_tiletype_index(tiletype_names, name)
  return tiletype_names[name] if tiletype_names.include?(name)
  idx = tiletype_names.length
  tiletype_names[name] = idx
  idx
end

constids = {}

class BinaryBlobAssembler
  def l(name, ltype = nil, export: false)
    if ltype.nil?
      puts "label #{name}"
    else
      puts "label #{name} #{ltype}"
    end
  end

  def r(name, comment)
    if comment.nil?
      puts "ref #{name}"
    else
      puts "ref #{name} #{comment}"
    end
  end

  def r_slice(name, length, comment)
    if comment.nil?
      puts "ref #{name}"
    else
      puts "ref #{name} #{comment}"
    end
    puts "u32 #{length}"
  end

  def s(str, comment)
    raise "|  must not appear in string" if str.include?("|")
    puts "str |#{str}| #{comment}"
  end

  def u8(v, comment)
    raise "value #{v} out of range for u8 (signed)" unless (-128..127).include?(v.to_i)
    if comment.nil?
      puts "u8 #{v}"
    else
      puts "u8 #{v} #{comment}"
    end
  end

  def u16(v, comment)
    # is actually used as signed 16 bit
    raise "value #{v} out of range for u16 (signed)" unless (-32768..32767).include?(v.to_i)
    if comment.nil?
      puts "u16 #{v}"
    else
      puts "u16 #{v} #{comment}"
    end
  end

  def u32(v, comment)
    if comment.nil?
      puts "u32 #{v}"
    else
      puts "u32 #{v} #{comment}"
    end
  end

  def pre(s)
    puts "pre #{s}"
  end

  def post(s)
    puts "post #{s}"
  end

  def push(name)
    puts "push #{name}"
  end

  def pop
    puts "pop"
  end
end

def get_bel_index(ddrg, loc, name, max_row)
  loctype = ddrg.locationTypes[ddrg.typeAtLocation[loc]]
  idx = 0
  loctype.bels.each do |bel|
    return idx if ddrg.to_str(bel.name) == name
    idx += 1
  end
  raise "Only missing IO should be special pins at bottom of device" unless loc.y == max_row
  nil
end

packages = {}
pindata = []

def process_pio_db(ddrg, device, max_row, constids, packages, pindata, package_filter = nil)
  piofile = File.join(Database.get_db_root(), "ECP5", device, "iodb.json")
  File.open(piofile, 'r') do |f|
    piodb = JSON.load(f)
    piodb["packages"].sort.each do |pkgname, pkgdata|
      if !package_filter.nil? && !package_filter.include?(pkgname)
        # we need to get the TQ144 package only out of the non-SERDES device
        # everything else comes from the SERDES device
        next
      end
      pins = []
      pkgdata.sort.each do |name, pinloc|
        x = pinloc["col"]
        y = pinloc["row"]
        loc = Pytrellis::Location.new(x, y)
        pio = "PIO" + pinloc["pio"]
        bel_idx = get_bel_index(ddrg, loc, pio, max_row)
        pins << [name, loc, bel_idx] unless bel_idx.nil?
      end
      packages[pkgname] = pins
    end
    if package_filter.nil?
      piodb["pio_metadata"].each do |metaitem|
        x = metaitem["col"]
        y = metaitem["row"]
        loc = Pytrellis::Location.new(x, y)
        pio = "PIO" + metaitem["pio"]
        bank = metaitem["bank"]
        pinfunc = metaitem.include?("function") ? metaitem["function"] : nil
        dqs = -1
        if metaitem.include?("dqs")
          tdqs = metaitem["dqs"]
          if tdqs[0] == "L"
            dqs = 0
          elsif tdqs[0] == "R"
            dqs = 2048
          end
          suffix_size = 0
          suffix_size += 1 while tdqs[-(suffix_size + 1)].match?(/\d/)
          dqs |= tdqs[-suffix_size..].to_i
        end
        bel_idx = get_bel_index(ddrg, loc, pio, max_row)
        pindata << [loc, bel_idx, bank, pinfunc, dqs] unless bel_idx.nil?
      end
    end
  end
end

global_data = {}
quadrants = ["UL", "UR", "LL", "LR"]

def process_loc_globals(chip, max_row, max_col, quadrants, global_data)
  (0..max_row).each do |y|
    (0..max_col).each do |x|
      quad = chip.global_data.get_quadrant(y, x)
      tapdrv = chip.global_data.get_tap_driver(y, x)
      if tapdrv.col == x
        spinedrv = chip.global_data.get_spine_driver(quad, x)
        spine = [spinedrv.second, spinedrv.first]
      else
        spine = [-1, -1]
      end
      global_data[[x, y]] = [quadrants.index(quad), tapdrv.dir.to_i, tapdrv.col, spine]
    end
  end
end

speed_grade_names = ["6", "7", "8", "8_5G"]
speed_grade_cells = {}
speed_grade_pips = {}

pip_class_to_idx = {"default" => 0, "zero" => 1}

timing_port_xform = {
  "RAD0" => "D0",
  "RAD1" => "B0",
  "RAD2" => "C0",
  "RAD3" => "A0",
}

delay_db = {}

# Convert from Lattice-style grouped SLICE to new nextpnr split style SLICE
def postprocess_timing_data(cells, delay_db, constids)
  delay_diff = ->(x, y) { [x[0] - y[0], x[1] - y[1]] }

  split_cells = {}
  comb_delays = {}
  comb_delays[["A", "F"]]    = delay_db["SLOGICB"][["A0", "F0"]]
  comb_delays[["B", "F"]]    = delay_db["SLOGICB"][["B0", "F0"]]
  comb_delays[["C", "F"]]    = delay_db["SLOGICB"][["C0", "F0"]]
  comb_delays[["D", "F"]]    = delay_db["SLOGICB"][["D0", "F0"]]
  comb_delays[["A", "OFX"]]  = delay_db["SLOGICB"][["A0", "OFX0"]]
  comb_delays[["B", "OFX"]]  = delay_db["SLOGICB"][["B0", "OFX0"]]
  comb_delays[["C", "OFX"]]  = delay_db["SLOGICB"][["C0", "OFX0"]]
  comb_delays[["D", "OFX"]]  = delay_db["SLOGICB"][["D0", "OFX0"]]
  comb_delays[["M", "OFX"]]  = delay_db["SLOGICB"][["M0", "OFX0"]] # worst case
  comb_delays[["F1", "OFX"]] = delay_diff.call(
    delay_db["SLOGICB"][["A1", "OFX0"]],
    delay_db["SLOGICB"][["A1", "F1"]]
  )
  comb_delays[["FXA", "OFX"]] = delay_db["SLOGICB"][["FXA", "OFX1"]]
  comb_delays[["FXB", "OFX"]] = delay_db["SLOGICB"][["FXB", "OFX1"]]
  split_cells["TRELLIS_COMB"] = comb_delays

  carry0_delays = {}
  carry0_delays[["A", "F"]]     = delay_db["SCCU2C"][["A0", "F0"]]
  carry0_delays[["B", "F"]]     = delay_db["SCCU2C"][["B0", "F0"]]
  carry0_delays[["C", "F"]]     = delay_db["SCCU2C"][["C0", "F0"]]
  carry0_delays[["D", "F"]]     = delay_db["SCCU2C"][["D0", "F0"]]
  carry0_delays[["A", "FCO"]]   = delay_db["SCCU2C"][["A0", "FCO"]]
  carry0_delays[["B", "FCO"]]   = delay_db["SCCU2C"][["B0", "FCO"]]
  carry0_delays[["C", "FCO"]]   = delay_db["SCCU2C"][["C0", "FCO"]]
  carry0_delays[["D", "FCO"]]   = delay_db["SCCU2C"][["D0", "FCO"]]
  carry0_delays[["FCI", "F"]]   = delay_db["SCCU2C"][["FCI", "F0"]]
  carry0_delays[["FCI", "FCO"]] = delay_db["SCCU2C"][["FCI", "FCO"]]
  split_cells["TRELLIS_COMB_CARRY0"] = carry0_delays

  carry1_delays = {}
  carry1_delays[["A", "F"]]     = delay_db["SCCU2C"][["A1", "F1"]]
  carry1_delays[["B", "F"]]     = delay_db["SCCU2C"][["B1", "F1"]]
  carry1_delays[["C", "F"]]     = delay_db["SCCU2C"][["C1", "F1"]]
  carry1_delays[["D", "F"]]     = delay_db["SCCU2C"][["D1", "F1"]]
  carry1_delays[["A", "FCO"]]   = delay_db["SCCU2C"][["A1", "FCO"]]
  carry1_delays[["B", "FCO"]]   = delay_db["SCCU2C"][["B1", "FCO"]]
  carry1_delays[["C", "FCO"]]   = delay_db["SCCU2C"][["C1", "FCO"]]
  carry1_delays[["D", "FCO"]]   = delay_db["SCCU2C"][["D1", "FCO"]]
  carry1_delays[["FCI", "F"]]   = delay_diff.call(
    delay_db["SCCU2C"][["FCI", "F1"]],
    delay_db["SCCU2C"][["FCI", "FCO"]]
  )
  carry1_delays[["FCI", "FCO"]] = [0, 0]
  split_cells["TRELLIS_COMB_CARRY1"] = carry1_delays

  split_cells.sort.each do |celltype, celldelays|
    delays = []
    setupholds = []
    celldelays.sort.each do |(from_pin, to_pin), (min_delay, max_delay)|
      delays << [constids[from_pin], constids[to_pin], min_delay, max_delay]
    end
    cells << [constids[celltype], delays, setupholds]
  end
end

def process_timing_data(speed_grade_names, delay_db, pip_class_to_idx,
                        speed_grade_cells, speed_grade_pips, timing_port_xform, constids)
  speed_grade_names.each do |grade|
    File.open(TimingDbs.cells_db_path("ECP5", grade)) do |f|
      cell_data = JSON.load(f)
      cells = []
      cell_data.sort.each do |cell, cdata|
        celltype = constids[cell.gsub(":", "_").gsub("=", "_").gsub(",", "_")]
        delays = []
        setupholds = []
        delay_db[cell] = {}
        cdata.each do |entry|
          if entry["type"] == "Width"
            next
          elsif entry["type"] == "IOPath"
            from_pin = entry["from_pin"].is_a?(Array) ? entry["from_pin"][1] : entry["from_pin"]
            from_pin = timing_port_xform[from_pin] if timing_port_xform.include?(from_pin)
            to_pin = entry["to_pin"]
            to_pin = timing_port_xform[to_pin] if timing_port_xform.include?(to_pin)
            min_delay = [entry["rising"][0], entry["falling"][0]].min
            max_delay = [entry["rising"][2], entry["falling"][2]].min
            delay_db[cell][[from_pin, to_pin]] = [min_delay, max_delay]
            delays << [constids[from_pin], constids[to_pin], min_delay, max_delay]
          elsif entry["type"] == "SetupHold"
            next if entry["pin"].is_a?(Array)
            pin = constids[entry["pin"]]
            clock = constids[entry["clock"][1]]
            min_setup = entry["setup"][0]
            max_setup = entry["setup"][2]
            min_hold = entry["hold"][0]
            max_hold = entry["hold"][2]
            setupholds << [pin, clock, min_setup, max_setup, min_hold, max_hold]
          else
            raise entry["type"]
          end
        end
        cells << [celltype, delays, setupholds]
      end
      postprocess_timing_data(cells, delay_db, constids)
      pip_class_delays = []
      pip_class_to_idx.length.times do
        pip_class_delays << [50, 50, 0, 0]
      end
      pip_class_delays[pip_class_to_idx["zero"]] = [0, 0, 0, 0]
      File.open(TimingDbs.interconnect_db_path("ECP5", grade)) do |f2|
        interconn_data = JSON.load(f2)
        interconn_data.sort.each do |pipclass, pipdata|
          min_delay  = pipdata["delay"][0] * 1.1
          max_delay  = pipdata["delay"][2] * 1.1
          min_fanout = pipdata["fanout"][0]
          max_fanout = pipdata["fanout"][2]
          if grade == "6"
            pip_class_to_idx[pipclass] = pip_class_delays.length
            pip_class_delays << [min_delay, max_delay, min_fanout, max_fanout]
          elsif pip_class_to_idx.include?(pipclass)
            pip_class_delays[pip_class_to_idx[pipclass]] = [min_delay, max_delay, min_fanout, max_fanout]
          end
        end
      end
      speed_grade_cells[grade] = cells
      speed_grade_pips[grade] = pip_class_delays
    end
  end
end

def get_pip_class(wire_from, wire_to, pip_class_to_idx)
  if wire_from.include?("FCO") || wire_to.include?("FCI")
    return pip_class_to_idx["zero"]
  end
  if wire_from.include?("F5") || wire_from.include?("FX") ||
     wire_to.include?("FXA") || wire_to.include?("FXB")
    return pip_class_to_idx["zero"]
  end

  class_name = PipClasses.get_pip_class(wire_from, wire_to)
  if class_name.nil? || !pip_class_to_idx.include?(class_name)
    class_name = "default"
  end
  pip_class_to_idx[class_name]
end

def write_database(dev_name, chip, ddrg, endianness,
                   max_row, max_col, tiletype_names, gfx_wire_ids,
                   packages, pindata, global_data, quadrants,
                   speed_grade_names, speed_grade_cells, speed_grade_pips,
                   pip_class_to_idx, constids, const_id_count)

  write_loc = ->(bba, loc, sym_name) do
    bba.u16(loc.x, "#{sym_name}.x")
    bba.u16(loc.y, "#{sym_name}.y")
  end

  loctypes = ddrg.locationTypes.map { |lt| lt.key() }
  loc_with_type = {}
  (0..max_row).each do |y|
    (0..max_col).each do |x|
      loc_with_type[loctypes.index(ddrg.typeAtLocation[Pytrellis::Location.new(x, y)])] = [x, y]
    end
  end

  get_wire_name = ->(arc_loctype, rel, idx) do
    loc = loc_with_type[arc_loctype]
    lt = ddrg.typeAtLocation[Pytrellis::Location.new(loc[0] + rel.x, loc[1] + rel.y)]
    wire = ddrg.locationTypes[lt].wires[idx]
    "R#{loc[1] + rel.y}C#{loc[0] + rel.x}_#{ddrg.to_str(wire.name)}"
  end

  bba = BinaryBlobAssembler.new
  bba.pre('#include "nextpnr.h"')
  bba.pre('#include "embed.h"')
  bba.pre('NEXTPNR_NAMESPACE_BEGIN')
  bba.post("EmbeddedFile chipdb_file_#{dev_name}(\"ecp5/chipdb-#{dev_name}.bin\", chipdb_blob_#{dev_name});")
  bba.post('NEXTPNR_NAMESPACE_END')
  bba.push("chipdb_blob_#{dev_name}")
  bba.r("chip_info", "chip_info")

  loctypes.length.times do |idx|
    loctype = ddrg.locationTypes[loctypes[idx]]
    if loctype.arcs.length > 0
      bba.l("loc#{idx}_pips", "PipInfoPOD")
      loctype.arcs.each do |arc|
        write_loc.call(bba, arc.srcWire.rel, "src")
        write_loc.call(bba, arc.sinkWire.rel, "dst")
        bba.u16(arc.srcWire.id, "src_idx")
        bba.u16(arc.sinkWire.id, "dst_idx")
        src_name = get_wire_name.call(idx, arc.srcWire.rel, arc.srcWire.id)
        snk_name = get_wire_name.call(idx, arc.sinkWire.rel, arc.sinkWire.id)
        bba.u16(get_pip_class(src_name, snk_name, pip_class_to_idx), "timing_class")
        bba.u8(get_tiletype_index(tiletype_names, ddrg.to_str(arc.tiletype)), "tile_type")
        cls = arc.cls
        cls = 2 if cls == 1 && ("PCS".include?(snk_name) || snk_name.include?("DCU") || src_name.include?("DCU"))
        bba.u8(cls, "pip_type")
        bba.u16(arc.lutperm_flags, "lutperm_flags")
        bba.u16(0, "padding")
      end
    end
    if loctype.wires.length > 0
      loctype.wires.length.times do |wire_idx|
        wire = loctype.wires[wire_idx]
        if wire.arcsDownhill.length > 0
          bba.l("loc#{idx}_wire#{wire_idx}_downpips", "PipLocatorPOD")
          wire.arcsDownhill.each do |dp|
            write_loc.call(bba, dp.rel, "rel_loc")
            bba.u32(dp.id, "index")
          end
        end
        if wire.arcsUphill.length > 0
          bba.l("loc#{idx}_wire#{wire_idx}_uppips", "PipLocatorPOD")
          wire.arcsUphill.each do |up|
            write_loc.call(bba, up.rel, "rel_loc")
            bba.u32(up.id, "index")
          end
        end
        if wire.belPins.length > 0
          bba.l("loc#{idx}_wire#{wire_idx}_belpins", "BelPortPOD")
          wire.belPins.each do |bp|
            write_loc.call(bba, bp.bel.rel, "rel_bel_loc")
            bba.u32(bp.bel.id, "bel_index")
            bba.u32(constids[ddrg.to_str(bp.pin)], "port")
          end
        end
      end
      bba.l("loc#{idx}_wires", "WireInfoPOD")
      loctype.wires.length.times do |wire_idx|
        wire = loctype.wires[wire_idx]
        bba.s(ddrg.to_str(wire.name), "name")
        bba.u16(constids[wire_type(ddrg.to_str(wire.name))], "type")
        tile_wire_key = "TILE_WIRE_" + ddrg.to_str(wire.name)
        if gfx_wire_ids.include?(tile_wire_key)
          bba.u16(gfx_wire_ids[tile_wire_key], "tile_wire")
        else
          bba.u16(0, "tile_wire")
        end
        uppips_label  = wire.arcsUphill.length   > 0 ? "loc#{idx}_wire#{wire_idx}_uppips"   : nil
        downpips_label = wire.arcsDownhill.length > 0 ? "loc#{idx}_wire#{wire_idx}_downpips" : nil
        belpins_label  = wire.belPins.length      > 0 ? "loc#{idx}_wire#{wire_idx}_belpins"  : nil
        bba.r_slice(uppips_label,   wire.arcsUphill.length,   "pips_uphill")
        bba.r_slice(downpips_label, wire.arcsDownhill.length, "pips_downhill")
        bba.r_slice(belpins_label,  wire.belPins.length,      "bel_pins")
      end
    end
    if loctype.bels.length > 0
      loctype.bels.length.times do |bel_idx|
        bel = loctype.bels[bel_idx]
        bba.l("loc#{idx}_bel#{bel_idx}_wires", "BelWirePOD")
        bel.wires.each do |pin|
          write_loc.call(bba, pin.wire.rel, "rel_wire_loc")
          bba.u32(pin.wire.id, "wire_index")
          bba.u32(constids[ddrg.to_str(pin.pin)], "port")
          bba.u32(pin.dir.to_i, "dir")
        end
      end
      bba.l("loc#{idx}_bels", "BelInfoPOD")
      loctype.bels.length.times do |bel_idx|
        bel = loctype.bels[bel_idx]
        bba.s(ddrg.to_str(bel.name), "name")
        bba.u32(constids[ddrg.to_str(bel.type)], "type")
        bba.u32(bel.z, "z")
        bba.r_slice("loc#{idx}_bel#{bel_idx}_wires", bel.wires.length, "bel_wires")
      end
    end
  end

  bba.l("locations", "LocationTypePOD")
  loctypes.length.times do |idx|
    loctype = ddrg.locationTypes[loctypes[idx]]
    bba.r_slice(loctype.bels.length  > 0 ? "loc#{idx}_bels"  : nil, loctype.bels.length,  "bel_data")
    bba.r_slice(loctype.wires.length > 0 ? "loc#{idx}_wires" : nil, loctype.wires.length, "wire_data")
    bba.r_slice(loctype.arcs.length  > 0 ? "loc#{idx}_pips"  : nil, loctype.arcs.length,  "pips_data")
  end

  (0..max_row).each do |y|
    (0..max_col).each do |x|
      bba.l("tile_info_#{x}_#{y}", "TileNamePOD")
      chip.get_tiles_by_position(y, x).each do |tile|
        bba.s(tile.info.name, "name")
        bba.u16(get_tiletype_index(tiletype_names, tile.info.type), "type_idx")
        bba.u16(0, "padding")
      end
    end
  end

  bba.l("tiles_info", "TileInfoPOD")
  (0..max_row).each do |y|
    (0..max_col).each do |x|
      bba.r_slice("tile_info_#{x}_#{y}", chip.get_tiles_by_position(y, x).length, "tile_names")
    end
  end

  bba.l("location_types", "int32_t")
  (0..max_row).each do |y|
    (0..max_col).each do |x|
      bba.u32(loctypes.index(ddrg.typeAtLocation[Pytrellis::Location.new(x, y)]), "loctype")
    end
  end

  bba.l("location_glbinfo", "GlobalInfoPOD")
  (0..max_row).each do |y|
    (0..max_col).each do |x|
      bba.u16(global_data[[x, y]][2],    "tap_col")
      bba.u8(global_data[[x, y]][1],     "tap_dir")
      bba.u8(global_data[[x, y]][0],     "quad")
      bba.u16(global_data[[x, y]][3][1], "spine_row")
      bba.u16(global_data[[x, y]][3][0], "spine_col")
    end
  end

  packages.sort.each do |package, pkgdata|
    bba.l("package_data_#{package}", "PackagePinPOD")
    pkgdata.each do |pin|
      name, loc, bel_idx = pin
      bba.s(name, "name")
      write_loc.call(bba, loc, "abs_loc")
      bba.u32(bel_idx, "bel_index")
    end
  end

  bba.l("package_data", "PackageInfoPOD")
  packages.sort.each do |package, pkgdata|
    bba.s(package, "name")
    bba.r_slice("package_data_#{package}", pkgdata.length, "pin_data")
  end

  bba.l("pio_info", "PIOInfoPOD")
  pindata.each do |pin|
    loc, bel_idx, bank, func, dqs = pin
    write_loc.call(bba, loc, "abs_loc")
    bba.u32(bel_idx, "bel_index")
    if !func.nil? && func != "WRITEN"
      bba.s(func, "function_name")
    else
      bba.r(nil, "function_name")
    end
    bba.u16(bank, "bank")
    bba.u16(dqs, "dqsgroup")
  end

  bba.l("tiletype_names", "RelPtr<char>")
  tiletype_names.sort_by { |_tt, idx| idx }.each do |tt, _idx|
    bba.s(tt, "name")
  end

  speed_grade_names.each do |grade|
    speed_grade_cells[grade].each do |cell|
      celltype, delays, setupholds = cell
      if delays.length > 0
        bba.l("cell_#{celltype}_delays_#{grade}")
        delays.each do |delay|
          from_pin, to_pin, min_delay, max_delay = delay
          bba.u32(from_pin, "from_pin")
          bba.u32(to_pin, "to_pin")
          bba.u32(min_delay, "min_delay")
          bba.u32(max_delay, "max_delay")
        end
      end
      if setupholds.length > 0
        bba.l("cell_#{celltype}_setupholds_#{grade}")
        setupholds.each do |sh|
          pin, clock, min_setup, max_setup, min_hold, max_hold = sh
          bba.u32(pin, "sig_port")
          bba.u32(clock, "clock_port")
          bba.u32(min_setup, "min_setup")
          bba.u32(max_setup, "max_setup")
          bba.u32(min_hold, "min_hold")
          bba.u32(max_hold, "max_hold")
        end
      end
    end
    bba.l("cell_timing_data_#{grade}")
    speed_grade_cells[grade].each do |cell|
      celltype, delays, setupholds = cell
      bba.u32(celltype, "cell_type")
      bba.r_slice(delays.length     > 0 ? "cell_#{celltype}_delays_#{grade}"     : nil, delays.length,     "delays")
      bba.r_slice(delays.length     > 0 ? "cell_#{celltype}_setupholds_#{grade}" : nil, setupholds.length, "setupholds")
    end
    bba.l("pip_timing_data_#{grade}")
    speed_grade_pips[grade].each do |pipclass|
      min_delay, max_delay, min_fanout, max_fanout = pipclass
      bba.u32(min_delay, "min_delay")
      bba.u32(max_delay, "max_delay")
      bba.u32(min_fanout, "min_fanout")
      bba.u32(max_fanout, "max_fanout")
    end
  end

  bba.l("speed_grade_data")
  speed_grade_names.each do |grade|
    bba.r_slice("cell_timing_data_#{grade}", speed_grade_cells[grade].length, "cell_timings")
    bba.r_slice("pip_timing_data_#{grade}",  speed_grade_pips[grade].length,  "pip_classes")
  end

  bba.l("chip_info")
  bba.u32(max_col + 1, "width")
  bba.u32(max_row + 1, "height")
  bba.u32((max_col + 1) * (max_row + 1), "num_tiles")
  bba.u32(const_id_count, "const_id_count")

  bba.r_slice("locations",       loctypes.length,                      "locations")
  bba.r_slice("location_types",  (max_col + 1) * (max_row + 1),        "location_type")
  bba.r_slice("location_glbinfo",(max_col + 1) * (max_row + 1),        "location_glbinfo")
  bba.r_slice("tiletype_names",  tiletype_names.length,                 "tiletype_names")
  bba.r_slice("package_data",    packages.length,                       "package_info")
  bba.r_slice("pio_info",        pindata.length,                        "pio_info")
  bba.r_slice("tiles_info",      (max_col + 1) * (max_row + 1),        "tile_info")
  bba.r_slice("speed_grade_data",speed_grade_names.length,              "speed_grades")

  bba.pop
  bba
end

dev_names = {"25k" => "LFE5UM5G-25F", "45k" => "LFE5UM5G-45F", "85k" => "LFE5UM5G-85F"}

def main(device_arg, options,
         location_types, type_at_location, tiletype_names,
         gfx_wire_ids, gfx_wire_names,
         constids, packages, pindata,
         global_data, quadrants,
         speed_grade_names, speed_grade_cells, speed_grade_pips,
         pip_class_to_idx, timing_port_xform, delay_db,
         dev_names)

  Pytrellis.load_database(Database.get_db_root())

  # Read port pin file
  const_id_count = 1 # count ID_NONE
  File.open(options[:constids]) do |f|
    f.each_line do |line|
      line = line.gsub("(", " ").gsub(")", " ")
      parts = line.split
      next if parts.empty?
      raise "expected 2 tokens, got #{parts.length}" unless parts.length == 2
      raise "expected X token" unless parts[0] == "X"
      idx = constids.length + 1
      constids[parts[1]] = idx
      const_id_count += 1
    end
  end

  constids["SLICE"] = constids["TRELLIS_SLICE"]
  constids["PIO"]   = constids["TRELLIS_IO"]

  # puts "Initialising chip..."
  chip = Pytrellis::Chip.new(dev_names[device_arg])
  # puts "Building routing graph..."
  ddrg = Pytrellis.make_dedup_chipdb(chip, include_lutperm_pips: true, split_slice_mode: true)
  max_row = chip.get_max_row()
  max_col = chip.get_max_col()

  process_timing_data(speed_grade_names, delay_db, pip_class_to_idx,
                      speed_grade_cells, speed_grade_pips, timing_port_xform, constids)
  process_pio_db(ddrg, dev_names[device_arg], max_row, constids, packages, pindata)
  # add TQFP144 package from non-SERDES device if appropriate
  process_pio_db(ddrg, "LFE5U-25F", max_row, constids, packages, pindata, Set["TQFP144"]) if device_arg == "25k"
  process_pio_db(ddrg, "LFE5U-45F", max_row, constids, packages, pindata, Set["TQFP144"]) if device_arg == "45k"
  process_loc_globals(chip, max_row, max_col, quadrants, global_data)
  # puts "#{ddrg.locationTypes.length} unique location types"
  write_database(device_arg, chip, ddrg, "le",
                 max_row, max_col, tiletype_names, gfx_wire_ids,
                 packages, pindata, global_data, quadrants,
                 speed_grade_names, speed_grade_cells, speed_grade_pips,
                 pip_class_to_idx, constids, const_id_count)
end

if __FILE__ == $PROGRAM_NAME
  main(device_arg, options,
       location_types, type_at_location, tiletype_names,
       gfx_wire_ids, gfx_wire_names,
       constids, packages, pindata,
       global_data, quadrants,
       speed_grade_names, speed_grade_cells, speed_grade_pips,
       pip_class_to_idx, timing_port_xform, delay_db,
       dev_names)
end
