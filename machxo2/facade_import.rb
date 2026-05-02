#!/usr/bin/env ruby
require 'optparse'
require 'json'
require 'set'

tiletype_names = {}
gfx_wire_ids = {}
gfx_wire_names = []

options = {}
libdirs = []

parser = OptionParser.new do |opts|
  opts.banner = "Usage: facade_import.rb [options] device"
  opts.on("-p", "--constids PATH", "path to constids.inc") { |v| options[:constids] = v }
  opts.on("-g", "--gfxh PATH", "path to gfx.h") { |v| options[:gfxh] = v }
  opts.on("-L", "--libdir PATH", "extra Ruby library path") { |v| libdirs << v }
end

parser.parse!

device = ARGV[0]
if device.nil?
  puts parser
  exit(1)
end

libdirs.each { |d| $LOAD_PATH.unshift(d) }

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
      # skip
    elsif state == 1
      idx = gfx_wire_ids.length
      name = line.strip.sub(/,$/, "")
      gfx_wire_ids[name] = idx
      gfx_wire_names << name
    end
  end
end

def wire_type(name)
  "WIRE_TYPE_NONE"
end

# Get the index for a tiletype
def get_tiletype_index(name, tiletype_names)
  return tiletype_names[name] if tiletype_names.key?(name)
  idx = tiletype_names.length
  tiletype_names[name] = idx
  idx
end

def package_shortname(long_name, family)
  if long_name.start_with?("CABGA")
    if family == "MachXO"
      "B" + long_name[5..]
    else
      "BG" + long_name[5..]
    end
  elsif long_name.start_with?("CSBGA")
    if family == "MachXO"
      "M" + long_name[5..]
    else
      "MG" + long_name[5..]
    end
  elsif long_name.start_with?("CSFBGA")
    "MG" + long_name[6..]
  elsif long_name.start_with?("UCBGA")
    "UMG" + long_name[5..]
  elsif long_name.start_with?("FPBGA")
    "FG" + long_name[5..]
  elsif long_name.start_with?("FTBGA")
    if family == "MachXO"
      "FT" + long_name[5..]
    else
      "FTG" + long_name[5..]
    end
  elsif long_name.start_with?("WLCSP")
    if family == "MachXO3D"
      "UTG" + long_name[5..]
    else
      "UWG" + long_name[5..]
    end
  elsif long_name.start_with?("TQFP")
    if family == "MachXO"
      "T" + long_name[4..]
    else
      "TG" + long_name[4..]
    end
  elsif long_name.start_with?("QFN")
    if family == "MachXO3D"
      "SG" + long_name[3..]
    else
      if long_name[3] == "8"
        "QN" + long_name[3..]
      else
        "SG" + long_name[3..]
      end
    end
  else
    puts "unknown package name " + long_name
    exit(-1)
  end
end

constids = {}

class BinaryBlobAssembler
  def l(name, ltype = nil, export = false)
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
    raise "|not allowed in string| #{str}" if str.include?("|")
    puts "str |#{str}| #{comment}"
  end

  def u8(v, comment)
    raise "u8 value #{v} out of range" unless (-128..127).include?(v.to_i)
    if comment.nil?
      puts "u8 #{v}"
    else
      puts "u8 #{v} #{comment}"
    end
  end

  def u16(v, comment)
    # is actually used as signed 16 bit
    raise "u16 value #{v} out of range" unless (-32768..32767).include?(v.to_i)
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

def get_bel_index(rg, loc, name)
  tile = rg.tiles[loc]
  idx = 0
  tile.bels.each do |bel|
    return idx if rg.to_str(bel.name) == name
    idx += 1
  end
  # FIXME: I/O pins can be missing in various rows. Is there a nice way to
  # assert on each device size?
  nil
end

packages = {}
pindata = []
variants = {}

def process_devices_db(family, device, variants)
  devicefile = File.join(Database.get_db_root(), "devices.json")
  File.open(devicefile, 'r') do |f|
    devicedb = JSON.parse(f.read)
    devicedb["families"][family]["devices"][device]["variants"].sort.each do |varname, vardata|
      variants[varname] = vardata
    end
  end
end

def process_pio_db(rg, device, packages, pindata, dev_family, dev_names)
  piofile = File.join(Database.get_db_root(), dev_family[device], dev_names[device], "iodb.json")
  File.open(piofile, 'r') do |f|
    piodb = JSON.parse(f.read)
    piodb["packages"].sort.each do |pkgname, pkgdata|
      pins = []
      pkgdata.sort.each do |name, pinloc|
        x = pinloc["col"]
        y = pinloc["row"]
        loc = Pytrellis::Location.new(x, y)
        pio = "PIO" + pinloc["pio"]
        bel_idx = get_bel_index(rg, loc, pio)
        pins << [name, loc, bel_idx] unless bel_idx.nil?
      end
      packages[pkgname] = pins
    end
    piodb["pio_metadata"].each do |metaitem|
      x = metaitem["col"]
      y = metaitem["row"]
      loc = Pytrellis::Location.new(x, y)
      pio = "PIO" + metaitem["pio"]
      bank = metaitem["bank"]
      pinfunc = metaitem.key?("function") ? metaitem["function"] : nil
      dqs = -1
      if metaitem.key?("dqs")
        # pass
        # tdqs = metaitem["dqs"]
        # if tdqs[0] == "L"
        #   dqs = 0
        # elsif tdqs[0] == "R"
        #   dqs = 2048
        # end
        # suffix_size = 0
        # while tdqs[-(suffix_size+1)].match?(/\d/)
        #   suffix_size += 1
        # end
        # dqs |= tdqs[-suffix_size..].to_i
      end
      bel_idx = get_bel_index(rg, loc, pio)
      pindata << [loc, bel_idx, bank, pinfunc, dqs] unless bel_idx.nil?
    end
  end
end

SPEED_GRADE_NAMES = {
  "MachXO2" => ["1", "2", "3", "4", "5", "6"],
  "MachXO3"  => ["5", "6"],
  "MachXO3D" => ["2", "3", "5", "6"]
}

speed_grade_cells = {}
speed_grade_pips = {}

pip_class_to_idx = {"default" => 0, "zero" => 1}

TIMING_PORT_XFORM = {
  "RAD0" => "A0",
  "RAD1" => "B0",
  "RAD2" => "C0",
  "RAD3" => "D0",
}

delay_db = {}

# Convert from Lattice-style grouped SLICE to new nextpnr split style SLICE
def postprocess_timing_data(cells, delay_db, constids)
  delay_diff = lambda { |x, y| [x[0] - y[0], x[1] - y[1]] }

  split_cells = {}
  comb_delays = {}
  comb_delays[["A", "F"]]    = delay_db["SLICE"][["A0", "F0"]]
  comb_delays[["B", "F"]]    = delay_db["SLICE"][["B0", "F0"]]
  comb_delays[["C", "F"]]    = delay_db["SLICE"][["C0", "F0"]]
  comb_delays[["D", "F"]]    = delay_db["SLICE"][["D0", "F0"]]
  comb_delays[["A", "OFX"]]  = delay_db["SLICE"][["A0", "OFX0"]]
  comb_delays[["B", "OFX"]]  = delay_db["SLICE"][["B0", "OFX0"]]
  comb_delays[["C", "OFX"]]  = delay_db["SLICE"][["C0", "OFX0"]]
  comb_delays[["D", "OFX"]]  = delay_db["SLICE"][["D0", "OFX0"]]
  comb_delays[["M", "OFX"]]  = delay_db["SLICE"][["M0", "OFX0"]] # worst case
  comb_delays[["F1", "OFX"]] = delay_diff.call(delay_db["SLICE"][["A1", "OFX0"]],
                                                delay_db["SLICE"][["A1", "F1"]])
  comb_delays[["FXA", "OFX"]] = delay_db["SLICE"][["FXA", "OFX1"]]
  comb_delays[["FXB", "OFX"]] = delay_db["SLICE"][["FXB", "OFX1"]]
  split_cells["TRELLIS_COMB"] = comb_delays

  carry0_delays = {}
  carry0_delays[["A", "F"]]   = delay_db["SLICE"][["A0", "F0"]]
  carry0_delays[["B", "F"]]   = delay_db["SLICE"][["B0", "F0"]]
  carry0_delays[["C", "F"]]   = delay_db["SLICE"][["C0", "F0"]]
  carry0_delays[["D", "F"]]   = delay_db["SLICE"][["D0", "F0"]]
  carry0_delays[["A", "FCO"]] = delay_db["SLICE"][["A0", "FCO"]]
  carry0_delays[["B", "FCO"]] = delay_db["SLICE"][["B0", "FCO"]]
  carry0_delays[["C", "FCO"]] = delay_db["SLICE"][["C0", "FCO"]]
  carry0_delays[["D", "FCO"]] = delay_db["SLICE"][["D0", "FCO"]]
  carry0_delays[["FCI", "F"]]   = delay_db["SLICE"][["FCI", "F0"]]
  carry0_delays[["FCI", "FCO"]] = delay_db["SLICE"][["FCI", "FCO"]]
  split_cells["TRELLIS_COMB_CARRY0"] = carry0_delays

  carry1_delays = {}
  carry1_delays[["A", "F"]]   = delay_db["SLICE"][["A1", "F1"]]
  carry1_delays[["B", "F"]]   = delay_db["SLICE"][["B1", "F1"]]
  carry1_delays[["C", "F"]]   = delay_db["SLICE"][["C1", "F1"]]
  carry1_delays[["D", "F"]]   = delay_db["SLICE"][["D1", "F1"]]
  carry1_delays[["A", "FCO"]] = delay_db["SLICE"][["A1", "FCO"]]
  carry1_delays[["B", "FCO"]] = delay_db["SLICE"][["B1", "FCO"]]
  carry1_delays[["C", "FCO"]] = delay_db["SLICE"][["C1", "FCO"]]
  carry1_delays[["D", "FCO"]] = delay_db["SLICE"][["D1", "FCO"]]
  carry1_delays[["FCI", "F"]]   = delay_diff.call(delay_db["SLICE"][["FCI", "F1"]], delay_db["SLICE"][["FCI", "FCO"]])
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

def process_timing_data(family, speed_grade_cells, speed_grade_pips, pip_class_to_idx, delay_db, constids)
  SPEED_GRADE_NAMES[family].each do |grade|
    cell_data = JSON.parse(File.read(TimingDbs.cells_db_path(family, grade)))
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
          from_pin = TIMING_PORT_XFORM[from_pin] if TIMING_PORT_XFORM.key?(from_pin)
          to_pin = entry["to_pin"]
          to_pin = TIMING_PORT_XFORM[to_pin] if TIMING_PORT_XFORM.key?(to_pin)
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
    pip_class_to_idx.length.times { pip_class_delays << [50, 50, 0, 0] }
    pip_class_delays[pip_class_to_idx["zero"]] = [0, 0, 0, 0]
    interconn_data = JSON.parse(File.read(TimingDbs.interconnect_db_path(family, grade)))
    interconn_data.sort.each do |pipclass, pipdata|
      min_delay  = pipdata["delay"][0] * 1.1
      max_delay  = pipdata["delay"][2] * 1.1
      min_fanout = pipdata["fanout"][0]
      max_fanout = pipdata["fanout"][2]
      if grade == SPEED_GRADE_NAMES[family][0]
        pip_class_to_idx[pipclass] = pip_class_delays.length
        pip_class_delays << [min_delay, max_delay, min_fanout, max_fanout]
      else
        if pip_class_to_idx.key?(pipclass)
          pip_class_delays[pip_class_to_idx[pipclass]] = [min_delay, max_delay, min_fanout, max_fanout]
        end
      end
    end
    speed_grade_cells[grade] = cells
    speed_grade_pips[grade] = pip_class_delays
  end
end

def get_pip_class(wire_from, wire_to, pip_class_to_idx)
  if wire_from.include?("FCO") || wire_to.include?("FCI")
    return pip_class_to_idx["zero"]
  end
  if wire_from.include?("F5") || wire_from.include?("FX") || wire_to.include?("FXA") || wire_to.include?("FXB")
    return pip_class_to_idx["zero"]
  end
  if wire_from.include?("JCLK")
    wire_from = wire_from.gsub("JCLK", "CLK")
  end
  class_name = PipClasses.get_pip_class(wire_from, wire_to)
  if class_name.nil? || !pip_class_to_idx.key?(class_name)
    class_name = "default"
  end
  pip_class_to_idx[class_name]
end

def write_database(family, dev_name, chip, rg, endianness,
                   args_device, tiletype_names, gfx_wire_ids,
                   constids, packages, pindata, variants,
                   speed_grade_cells, speed_grade_pips, pip_class_to_idx,
                   max_row, max_col, const_id_count)

  write_loc = lambda do |loc, sym_name|
    bba.u16(loc.x, "#{sym_name}.x")
    bba.u16(loc.y, "#{sym_name}.y")
  end

  # Use Lattice naming conventions, so convert to 1-based col indexing.
  get_wire_name = lambda do |loc, idx|
    tile = rg.tiles[loc]
    "R#{loc.y}C#{loc.x + 1}_#{rg.to_str(tile.wires[idx].name)}"
  end

  # Before doing anything, ensure sorted routing graph iteration matches y, x
  loc_iter = rg.tiles.sort { |a, b| [a.y, a.x] <=> [b.y, b.x] }

  i = 1 # Drop (-2, -2) location.
  (0..max_row).each do |y|
    (0..max_col).each do |x|
      l = loc_iter[i]
      raise "location mismatch: expected (#{y}, #{x}), got (#{l.y}, #{l.x})" unless [y, x] == [l.y, l.x]
      i += 1
    end
  end

  bba = BinaryBlobAssembler.new
  bba.pre('#include "nextpnr.h"')
  bba.pre('#include "embed.h"')
  bba.pre('NEXTPNR_NAMESPACE_BEGIN')
  bba.post("EmbeddedFile chipdb_file_#{dev_name}(\"machxo2/chipdb-#{dev_name}.bin\", chipdb_blob_#{dev_name});")
  bba.post('NEXTPNR_NAMESPACE_END')
  bba.push("chipdb_blob_#{args_device}")
  bba.r("chip_info", "chip_info")

  # Nominally should be in order, but support situations where ruby
  # decides to iterate over rg.tiles out-of-order.
  loc_iter.each do |l|
    t = rg.tiles[l]

    # Do not include special globals location for now.
    next if [l.x, l.y] == [-2, -2]

    if t.arcs.length > 0
      bba.l("loc#{l.y}_#{l.x}_pips", "PipInfoPOD")
      t.arcs.each do |arc|
        write_loc.call(arc.srcWire.rel, "src")
        write_loc.call(arc.sinkWire.rel, "dst")
        bba.u16(arc.srcWire.id, "src_idx #{get_wire_name.call(arc.srcWire.rel, arc.srcWire.id)}")
        bba.u16(arc.sinkWire.id, "dst_idx #{get_wire_name.call(arc.sinkWire.rel, arc.sinkWire.id)}")
        src_name = get_wire_name.call(arc.srcWire.rel, arc.srcWire.id)
        snk_name = get_wire_name.call(arc.sinkWire.rel, arc.sinkWire.id)
        bba.u16(get_pip_class(src_name, snk_name, pip_class_to_idx), "timing_class")
        bba.u8(get_tiletype_index(rg.to_str(arc.tiletype), tiletype_names), "tile_type")
        cls = arc.cls
        bba.u8(cls, "pip_type")
        bba.u16(arc.lutperm_flags, "lutperm_flags")
        bba.u16(0, "padding")
      end
    end

    if t.wires.length > 0
      t.wires.length.times do |wire_idx|
        wire = t.wires[wire_idx]
        if wire.arcsDownhill.length > 0
          bba.l("loc#{l.y}_#{l.x}_wire#{wire_idx}_downpips", "PipLocatorPOD")
          wire.arcsDownhill.each do |dp|
            write_loc.call(dp.rel, "rel_loc")
            bba.u32(dp.id, "index")
          end
        end
        if wire.arcsUphill.length > 0
          bba.l("loc#{l.y}_#{l.x}_wire#{wire_idx}_uppips", "PipLocatorPOD")
          wire.arcsUphill.each do |up|
            write_loc.call(up.rel, "rel_loc")
            bba.u32(up.id, "index")
          end
        end
        if wire.belPins.length > 0
          bba.l("loc#{l.y}_#{l.x}_wire#{wire_idx}_belpins", "BelPortPOD")
          wire.belPins.each do |bp|
            write_loc.call(bp.bel.rel, "rel_bel_loc")
            bba.u32(bp.bel.id, "bel_index")
            bba.u32(constids[rg.to_str(bp.pin)], "port")
          end
        end
      end

      bba.l("loc#{l.y}_#{l.x}_wires", "WireInfoPOD")
      t.wires.length.times do |wire_idx|
        wire = t.wires[wire_idx]
        bba.s(rg.to_str(wire.name), "name")
        bba.u16(constids[wire_type(rg.to_str(wire.name))], "type")
        if gfx_wire_ids.key?("TILE_WIRE_" + rg.to_str(wire.name))
          bba.u16(gfx_wire_ids["TILE_WIRE_" + rg.to_str(wire.name)], "tile_wire")
        else
          bba.u16(0, "tile_wire")
        end
        bba.r_slice(wire.arcsUphill.length > 0 ? "loc#{l.y}_#{l.x}_wire#{wire_idx}_uppips" : nil,
                    wire.arcsUphill.length, "pips_uphill")
        bba.r_slice(wire.arcsDownhill.length > 0 ? "loc#{l.y}_#{l.x}_wire#{wire_idx}_downpips" : nil,
                    wire.arcsDownhill.length, "pips_downhill")
        bba.r_slice(wire.belPins.length > 0 ? "loc#{l.y}_#{l.x}_wire#{wire_idx}_belpins" : nil,
                    wire.belPins.length, "bel_pins")
      end
    end

    if t.bels.length > 0
      t.bels.length.times do |bel_idx|
        bel = t.bels[bel_idx]
        bba.l("loc#{l.y}_#{l.x}_bel#{bel_idx}_wires", "BelWirePOD")
        bel.wires.each do |pin|
          write_loc.call(pin.wire.rel, "rel_wire_loc")
          bba.u32(pin.wire.id, "wire_index")
          bba.u32(constids[rg.to_str(pin.pin)], "port")
          bba.u32(pin.dir.to_i, "type")
        end
      end
      bba.l("loc#{l.y}_#{l.x}_bels", "BelInfoPOD")
      t.bels.length.times do |bel_idx|
        bel = t.bels[bel_idx]
        bba.s(rg.to_str(bel.name), "name")
        bba.u32(constids[rg.to_str(bel.type)], "type")
        bba.u32(bel.z, "z")
        bba.r_slice("loc#{l.y}_#{l.x}_bel#{bel_idx}_wires", bel.wires.length, "bel_wires")
      end
    end
  end

  bba.l("tiles", "TileTypePOD")
  loc_iter.each do |l|
    t = rg.tiles[l]

    next if [l.y, l.x] == [-2, -2]

    bba.r_slice(t.bels.length > 0 ? "loc#{l.y}_#{l.x}_bels" : nil, t.bels.length, "bel_data")
    bba.r_slice(t.wires.length > 0 ? "loc#{l.y}_#{l.x}_wires" : nil, t.wires.length, "wire_data")
    bba.r_slice(t.arcs.length > 0 ? "loc#{l.y}_#{l.x}_pips" : nil, t.arcs.length, "pips_data")
  end

  (0..max_row).each do |y|
    (0..max_col).each do |x|
      bba.l("tile_info_#{x}_#{y}", "TileNamePOD")
      chip.get_tiles_by_position(y, x).each do |tile|
        bba.s(tile.info.name, "name")
        bba.u16(get_tiletype_index(tile.info.type, tiletype_names), "type_idx")
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

  packages.sort.each do |package, pkgdata|
    bba.l("package_data_#{package}", "PackagePinPOD")
    pkgdata.each do |pin|
      name, loc, bel_idx = pin
      bba.s(name, "name")
      write_loc.call(loc, "abs_loc")
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
    write_loc.call(loc, "abs_loc")
    bba.u32(bel_idx, "bel_index")
    if !func.nil? && func != "WRITEN"
      bba.s(func, "function_name")
    else
      bba.r(nil, "function_name")
    end
    # TODO: io_grouping? And DQS.
    bba.u16(bank, "bank")
    bba.u16(dqs, "dqsgroup")
  end

  bba.l("tiletype_names", "RelPtr<char>")
  tiletype_names.sort_by { |tt, idx| idx }.each do |tt, idx|
    bba.s(tt, "name")
  end

  SPEED_GRADE_NAMES[family].each do |grade|
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
      bba.r_slice(delays.length > 0 ? "cell_#{celltype}_delays_#{grade}" : nil, delays.length, "delays")
      bba.r_slice(delays.length > 0 ? "cell_#{celltype}_setupholds_#{grade}" : nil, setupholds.length, "setupholds")
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
  SPEED_GRADE_NAMES[family].each do |grade|
    bba.r_slice("cell_timing_data_#{grade}", speed_grade_cells[grade].length, "cell_timings")
    bba.r_slice("pip_timing_data_#{grade}", speed_grade_pips[grade].length, "pip_classes")
  end

  variants.sort.each do |name, var_data|
    bba.l("supported_packages_#{name}", "PackageSupportedPOD")
    var_data["packages"].each do |package|
      bba.s(package, "name")
      bba.s(package_shortname(package, chip.info.family), "short_name")
    end
    bba.l("supported_speed_grades_#{name}", "SpeedSupportedPOD")
    var_data["speeds"].each do |speed|
      bba.u16(speed, "speed")
      bba.u16(SPEED_GRADE_NAMES[family].index(speed.to_s), "index")
    end
    bba.l("supported_suffixes_#{name}", "SuffixeSupportedPOD")
    var_data["suffixes"].each do |suffix|
      bba.s(suffix, "suffix")
    end
  end

  bba.l("variant_data", "VariantInfoPOD")
  variants.sort.each do |name, var_data|
    bba.s(name, "variant_name")
    bba.r_slice("supported_packages_#{name}", var_data["packages"].length, "supported_packages")
    bba.r_slice("supported_speed_grades_#{name}", var_data["speeds"].length, "supported_speed_grades")
    bba.r_slice("supported_suffixes_#{name}", var_data["suffixes"].length, "supported_suffixes")
  end

  bba.l("spine_info", "SpineInfoPOD")
  spines = chip.global_data_machxo2.spines
  spines.each do |spine|
    bba.u32(spine.row, "row")
  end

  bba.l("chip_info")
  bba.s(chip.info.family, "family")
  bba.s(chip.info.name, "device_name")
  bba.u32(max_col + 1, "width")
  bba.u32(max_row + 1, "height")
  bba.u32((max_col + 1) * (max_row + 1), "num_tiles")
  bba.u32(const_id_count, "const_id_count")

  bba.r_slice("tiles", (max_col + 1) * (max_row + 1), "tiles")
  bba.r_slice("tiletype_names", tiletype_names.length, "tiletype_names")
  bba.r_slice("package_data", packages.length, "package_info")
  bba.r_slice("pio_info", pindata.length, "pio_info")
  bba.r_slice("tiles_info", (max_col + 1) * (max_row + 1), "tile_info")
  bba.r_slice("variant_data", variants.length, "variant_info")
  bba.r_slice("spine_info", spines.length, "spine_info")
  bba.r_slice("speed_grade_data", SPEED_GRADE_NAMES[family].length, "speed_grades")

  bba.pop
  bba
end

DEV_FAMILY = {
  "256X"  => "MachXO",
  "640X"  => "MachXO",
  "1200X" => "MachXO",
  "2280X" => "MachXO",

  "256"   => "MachXO2",
  "640"   => "MachXO2",
  "1200"  => "MachXO2",
  "2000"  => "MachXO2",
  "4000"  => "MachXO2",
  "7000"  => "MachXO2",

  "1300"  => "MachXO3",
  "2100"  => "MachXO3",
  "4300"  => "MachXO3",
  "6900"  => "MachXO3",
  "9400"  => "MachXO3",

  "4300D" => "MachXO3D",
  "9400D" => "MachXO3D"
}

DEV_NAMES = {
  "256X"  => "LCMXO256",
  "640X"  => "LCMXO640",
  "1200X" => "LCMXO1200",
  "2280X" => "LCMXO2280",

  "256"   => "LCMXO2-256",
  "640"   => "LCMXO2-640",
  "1200"  => "LCMXO2-1200",
  "2000"  => "LCMXO2-2000",
  "4000"  => "LCMXO2-4000",
  "7000"  => "LCMXO2-7000",

  "1300"  => "LCMXO3-1300",
  "2100"  => "LCMXO3-2100",
  "4300"  => "LCMXO3-4300",
  "6900"  => "LCMXO3-6900",
  "9400"  => "LCMXO3-9400",

  "4300D" => "LCMXO3D-4300",
  "9400D" => "LCMXO3D-9400"
}

def main(device, options, libdirs, tiletype_names, gfx_wire_ids)
  constids = {}
  packages = {}
  pindata = []
  variants = {}
  speed_grade_cells = {}
  speed_grade_pips = {}
  pip_class_to_idx = {"default" => 0, "zero" => 1}
  delay_db = {}

  Pytrellis.load_database(Database.get_db_root())

  const_id_count = 1 # count ID_NONE
  File.open(options[:constids]) do |f|
    f.each_line do |line|
      line = line.gsub("(", " ").gsub(")", " ")
      line = line.split
      next if line.empty?
      raise "expected 2 tokens, got #{line.length}" unless line.length == 2
      raise "expected 'X', got '#{line[0]}'" unless line[0] == "X"
      idx = constids.length + 1
      constids[line[1]] = idx
      const_id_count += 1
    end
  end

  constids["SLICE"] = constids["TRELLIS_SLICE"]
  constids["PIO"]   = constids["TRELLIS_IO"]

  chip = Pytrellis::Chip.new(DEV_NAMES[device])
  rg = Pytrellis.make_optimized_chipdb(chip, include_lutperm_pips: true, split_slice_mode: true)
  max_row = chip.get_max_row()
  max_col = chip.get_max_col()
  process_timing_data(DEV_FAMILY[device], speed_grade_cells, speed_grade_pips, pip_class_to_idx, delay_db, constids)
  process_pio_db(rg, device, packages, pindata, DEV_FAMILY, DEV_NAMES)
  process_devices_db(chip.info.family, chip.info.name, variants)
  write_database(DEV_FAMILY[device], device, chip, rg, "le",
                 device, tiletype_names, gfx_wire_ids,
                 constids, packages, pindata, variants,
                 speed_grade_cells, speed_grade_pips, pip_class_to_idx,
                 max_row, max_col, const_id_count)
end

if __FILE__ == $PROGRAM_NAME
  main(device, options, libdirs, tiletype_names, gfx_wire_ids)
end
