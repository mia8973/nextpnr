require 'json'
require 'set'
require_relative 'tileconn'
require_relative 'parse_sdf'
# Represents Xilinx device data from PrjXray etc

class WireData
  attr_accessor :index, :name, :intent, :tied_value, :resistance, :capacitance
  def initialize(index:, name:, intent: "", tied_value: nil, resistance: 0, capacitance: 0)
    @index = index
    @name = name
    @intent = intent
    @tied_value = tied_value
    @resistance = resistance
    @capacitance = capacitance
  end
end

class PIPData
  attr_accessor :index, :from_wire, :to_wire, :is_bidi, :is_route_thru, :is_buffered,
                :min_delay, :max_delay, :resistance, :capacitance
  def initialize(index:, from_wire:, to_wire:, is_bidi: false, is_route_thru: false,
                 is_buffered: false, min_delay: 0, max_delay: 0, resistance: 0, capacitance: 0)
    @index = index
    @from_wire = from_wire
    @to_wire = to_wire
    @is_bidi = is_bidi
    @is_route_thru = is_route_thru
    @is_buffered = is_buffered
    @min_delay = min_delay
    @max_delay = max_delay
    @resistance = resistance
    @capacitance = capacitance
  end
end

class SiteWireData
  attr_accessor :name, :is_pin
  def initialize(name:, is_pin: false)
    @name = name
    @is_pin = is_pin
  end
end

class SiteBELPinData
  attr_accessor :name, :pindir, :site_wire_idx
  def initialize(name:, pindir:, site_wire_idx:)
    @name = name
    @pindir = pindir
    @site_wire_idx = site_wire_idx
  end
end

class SiteBELData
  attr_accessor :name, :bel_type, :bel_class, :pins
  def initialize(name:, bel_type:, bel_class:, pins:)
    @name = name
    @bel_type = bel_type
    @bel_class = bel_class
    @pins = pins
  end
end

class SitePIPData
  attr_accessor :bel_idx, :bel_input, :from_wire_idx, :to_wire_idx
  def initialize(bel_idx:, bel_input:, from_wire_idx:, to_wire_idx:)
    @bel_idx = bel_idx
    @bel_input = bel_input
    @from_wire_idx = from_wire_idx
    @to_wire_idx = to_wire_idx
  end
end

class SitePinData
  attr_accessor :name, :pindir, :site_wire_idx, :prim_pin_name
  def initialize(name:, pindir:, site_wire_idx:, prim_pin_name:)
    @name = name
    @pindir = pindir
    @site_wire_idx = site_wire_idx
    @prim_pin_name = prim_pin_name
  end
end

class SiteData
  attr_accessor :site_type, :wires, :bels, :pips, :pins, :variants
  def initialize(site_type)
    @site_type = site_type
    @wires = []
    @bels = []
    @pips = []
    @pins = []
    @variants = {}
  end
end

class TileSitePinData
  attr_accessor :wire_idx, :min_delay, :max_delay, :resistance, :capacitance
  def initialize(wire_idx)
    @wire_idx = wire_idx
    @min_delay = 0
    @max_delay = 0
    @resistance = 0
    @capacitance = 0
  end
end

class TileData
  attr_accessor :tile_type, :wires, :wires_by_name, :pips, :sitepin_data, :cell_timing
  def initialize(tile_type)
    @tile_type = tile_type
    @wires = []
    @wires_by_name = {}
    @pips = []
    @sitepin_data = {} # [type, relxy, pin] -> TileSitePinData
    @cell_timing = nil
  end
end

class PIP
  attr_accessor :tile, :index, :data
  def initialize(tile, index)
    @tile = tile
    @index = index
    @data = tile.get_pip_data(index)
  end
  def src_wire
    Wire.new(@tile, @data.from_wire)
  end
  def dst_wire
    Wire.new(@tile, @data.to_wire)
  end
  def is_route_thru
    @data.is_route_thru
  end
  alias route_thru? is_route_thru
  def is_bidi
    @data.is_bidi
  end
  def is_buffered
    @data.is_buffered
  end
  def min_delay
    @data.min_delay
  end
  def max_delay
    @data.max_delay
  end
  def resistance
    @data.resistance
  end
  def capacitance
    @data.capacitance
  end
end

class Wire
  attr_accessor :tile, :index, :data
  def initialize(tile, index)
    @tile = tile
    @index = index
    @data = tile.get_wire_data(index)
  end
  def name
    @data.name
  end
  def intent
    @data.intent
  end
  def node
    unless @tile.wire_to_node.key?(@index)
      @tile.wire_to_node[@index] = Node.new(@tile, [self])
    end
    @tile.wire_to_node[@index]
  end
  def is_gnd
    name.include?("GND_WIRE")
  end
  def is_vcc
    name.include?("VCC_WIRE")
  end
  def resistance
    @data.resistance
  end
  def capacitance
    @data.capacitance
  end
end

class SiteWire
  attr_accessor :site, :index, :data
  def initialize(site, index)
    @site = site
    @index = index
    @data = @site.get_wire_data(index)
  end
  def name
    @data.name
  end
end

class SiteBELPin
  attr_accessor :bel, :pin_name, :data
  def initialize(bel, name)
    @bel = bel
    @pin_name = name
    @data = @bel.data.pins[name]
  end
  def name
    @pin_name
  end
  def dir
    @data.pindir
  end
  def site_wire
    SiteWire.new(@bel.site, @data.site_wire_idx)
  end
end

class SiteBEL
  attr_accessor :site, :index, :data
  def initialize(site, index)
    @site = site
    @index = index
    @data = site.get_bel_data(index)
  end
  def name
    @data.name
  end
  def bel_type
    @data.bel_type
  end
  def bel_class
    @data.bel_class
  end
  def pins
    @data.pins.keys.map { |n| SiteBELPin.new(self, n) }
  end
end

class SitePIP
  attr_accessor :site, :index, :data
  def initialize(site, index)
    @site = site
    @index = index
    @data = site.get_pip_data(index)
  end
  def bel
    SiteBEL.new(@site, @data.bel_idx)
  end
  def bel_input
    @data.bel_input
  end
  def src_wire
    SiteWire.new(@site, @data.from_wire_idx)
  end
  def dst_wire
    SiteWire.new(@site, @data.to_wire_idx)
  end
end

class SitePin
  attr_accessor :site, :index, :data
  def initialize(site, index)
    @site = site
    @index = index
    @data = site.data.pins[index]
  end
  def name
    @data.name
  end
  def dir
    @data.pindir
  end
  def site_wire
    SiteWire.new(@site, @data.site_wire_idx)
  end
  def tile_wire
    @site.tile.site_pin_wire(@site.primary.site_type, @site.rel_xy, @data.prim_pin_name)
  end
  def min_delay
    @site.tile.site_pin_timing(@site.primary.site_type, @site.rel_xy, @data.prim_pin_name).min_delay
  end
  def max_delay
    @site.tile.site_pin_timing(@site.primary.site_type, @site.rel_xy, @data.prim_pin_name).max_delay
  end
  def resistance
    @site.tile.site_pin_timing(@site.primary.site_type, @site.rel_xy, @data.prim_pin_name).resistance
  end
  def capacitance
    @site.tile.site_pin_timing(@site.primary.site_type, @site.rel_xy, @data.prim_pin_name).capacitance
  end
end

class Site
  attr_accessor :tile, :name, :index, :prefix, :grid_xy, :data, :primary
  def initialize(tile, name, index, grid_xy, data, primary = nil)
    @tile = tile
    @name = name
    @index = index
    @prefix = name[0, name.rindex('_')]
    @grid_xy = grid_xy
    @data = data
    @primary = primary.nil? ? self : primary
    @_rel_xy = nil
    @_variants = nil
  end
  def get_bel_data(index)
    @data.bels[index]
  end
  def get_wire_data(index)
    @data.wires[index]
  end
  def get_pip_data(index)
    @data.pips[index]
  end
  def site_type
    @data.site_type
  end
  def rel_xy
    if @_rel_xy.nil?
      base_x = 999999
      base_y = 999999
      @tile.sites.each do |site|
        next if site.prefix != @prefix
        base_x = [base_x, site.grid_xy[0]].min
        base_y = [base_y, site.grid_xy[1]].min
      end
      @_rel_xy = [@grid_xy[0] - base_x, @grid_xy[1] - base_y]
    end
    @_rel_xy
  end
  def bels
    @data.bels.length.times.map { |i| SiteBEL.new(self, i) }
  end
  def wires
    @data.wires.length.times.map { |i| SiteWire.new(self, i) }
  end
  def pips
    @data.pips.length.times.map { |i| SitePIP.new(self, i) }
  end
  def pins
    @data.pins.length.times.map { |i| SitePin.new(self, i) }
  end
  def pin(p)
    @data.pins.length.times.each do |i|
      return SitePin.new(self, i) if @data.pins[i].name == p
    end
    nil
  end
  def available_variants
    # Make sure primary type is first
    if @_variants.nil?
      @_variants = []
      @_variants << site_type
      @data.variants.keys.sort.each do |var|
        @_variants << var if var != site_type
      end
    end
    @_variants
  end
  def variant(vtype)
    vsite = Site.new(@tile, @name, @index, @grid_xy, @data.variants[vtype], self)
    vsite
  end
  def rel_name
    x, y = rel_xy
    "#{@prefix}_X#{x}Y#{y}"
  end
end

class Tile
  attr_accessor :x, :y, :name, :data, :interconn_xy, :site_insts, :wire_to_node, :node_autoidx, :used_wires
  def initialize(x, y, name, data, interconn_xy, site_insts)
    @x = x
    @y = y
    @name = name
    @data = data
    @interconn_xy = interconn_xy
    @site_insts = site_insts
    @wire_to_node = {}
    @node_autoidx = 0
    @used_wires = nil
  end
  def get_pip_data(i)
    @data.pips[i]
  end
  def get_wire_data(i)
    @data.wires[i]
  end
  def tile_type
    @data.tile_type
  end
  def wires
    @data.wires.length.times.map { |i| Wire.new(self, i) }
  end
  def wire(name)
    Wire.new(self, @data.wires_by_name[name].index)
  end
  def pips
    @data.pips.length.times.map { |i| PIP.new(self, i) }
  end
  def sites
    @site_insts
  end
  def site_pin_wire(sitetype, rel_xy, pin)
    wire_idx = @data.sitepin_data[[sitetype, rel_xy, pin]].wire_idx
    wire_idx.nil? ? nil : Wire.new(self, wire_idx)
  end
  def site_pin_timing(sitetype, rel_xy, pin)
    @data.sitepin_data[[sitetype, rel_xy, pin]]
  end
  def cell_timing
    @data.cell_timing
  end
  def used_wire_indices
    if @used_wires.nil?
      @used_wires = Set.new
      pips.each do |pip|
        @used_wires.add(pip.src_wire.index)
        @used_wires.add(pip.dst_wire.index)
      end
      sites.each do |site|
        site.available_variants.each do |v|
          variant = site.variant(v)
          variant.pins.each do |pin|
            @used_wires.add(pin.tile_wire.index) unless pin.tile_wire.nil?
          end
        end
      end
    end
    @used_wires
  end
  def split_name
    prefix, xy = @name.rsplit("_", 2)
    xy_m = xy.match(/X(\d+)Y(\d+)/)
    [prefix, xy_m[1].to_i, xy_m[2].to_i]
  end
end

class Node
  attr_accessor :tile, :index, :wires
  def initialize(tile, wires = [])
    @tile = tile
    @index = tile.node_autoidx
    tile.node_autoidx += 1
    @wires = wires
  end
  def unique_index
    (@tile.y << 48) | (@tile.x << 32) | @index
  end
  def is_vcc
    @wires.any? { |wire| wire.is_vcc }
  end
  def is_gnd
    @wires.any? { |wire| wire.is_gnd }
  end
end

class Package
  attr_accessor :name, :pin_map
  def initialize(name)
    @name = name
    @pin_map = {}
  end
end

class Device
  attr_accessor :name, :tiles, :tiles_by_name, :tiles_by_xy, :sites_by_name, :width, :height, :packages
  def initialize(name)
    @name = name
    @tiles = []
    @tiles_by_name = {}
    @tiles_by_xy = {}
    @sites_by_name = {}
    @width = 0
    @height = 0
    @packages = {}
  end
  def tile(name)
    @tiles_by_name[name]
  end
  def site(name)
    @sites_by_name[name]
  end
end

def import_device(fabricname, prjxray_root, metadata_root)
  site_type_cache = {}
  tile_type_cache = {}
  tile_json_cache = {}

  parse_xy = lambda do |xy|
    xpos = xy.rindex("X")
    ypos = xy.rindex("Y")
    [xy[xpos+1...ypos].to_i, xy[ypos+1..].to_i]
  end

  get_site_type_data = lambda do |sitetype|
    unless site_type_cache.key?(sitetype)
      sd = SiteData.new(sitetype)
      sp = "#{metadata_root}/site_type_#{sitetype}.json"
      if File.exist?(sp)
        sj = File.open(sp, "r") { |jf| JSON.load(jf) }
        sj.sort.each do |vtype, vdata| # Consider all site variants
          if vtype == sitetype
            vd = sd # primary variant
          else
            vd = SiteData.new(vtype)
          end
          site_wire_by_name = {}
          wire_index = lambda do |wname|
            unless site_wire_by_name.key?(wname)
              idx = vd.wires.length
              vd.wires << SiteWireData.new(name: wname)
              site_wire_by_name[wname] = idx
            end
            site_wire_by_name[wname]
          end
          # Import bels
          bel_idx_by_name = {}
          vdata["bels"].sort.each do |bel, beldata|
            belpins = {}
            beldata["pins"].sort.each do |pin, pindata|
              belpins[pin] = SiteBELPinData.new(name: pin, pindir: pindata["dir"], site_wire_idx: wire_index.call(pindata["wire"]))
            end
            bd = SiteBELData.new(name: bel, bel_type: beldata["type"], bel_class: beldata["class"], pins: belpins)
            bel_idx_by_name[bel] = vd.bels.length
            vd.bels << bd
          end
          # Import pips
          vdata["pips"].each do |pipdata|
            bel_idx = bel_idx_by_name[pipdata["bel"]]
            bel_data = vd.bels[bel_idx]
            vd.pips << SitePIPData.new(
              bel_idx: bel_idx_by_name[pipdata["bel"]],
              bel_input: pipdata["from_pin"],
              from_wire_idx: bel_data.pins[pipdata["from_pin"]].site_wire_idx,
              to_wire_idx: bel_data.pins[pipdata["to_pin"]].site_wire_idx
            )
          end
          # Import pins
          vdata["pins"].sort.each do |pin, pindata|
            vd.pins << SitePinData.new(name: pin, pindir: pindata["dir"], site_wire_idx: wire_index.call(pindata["wire"]),
              prim_pin_name: pindata["primary"])
          end
          sd.variants[vtype] = vd
        end
      else
        sd.variants[sitetype] = sd
      end
      site_type_cache[sitetype] = sd
    end
    site_type_cache[sitetype]
  end

  read_tile_type_json = lambda do |tiletype|
    unless tile_json_cache.key?(tiletype)
      if !File.exist?("#{prjxray_root}/tile_type_#{tiletype}.json")
        tile_json_cache[tiletype] = {"wires" => {}, "pips" => {}, "sites" => []}
      else
        File.open("#{prjxray_root}/tile_type_#{tiletype}.json", "r") do |jf|
          tile_json_cache[tiletype] = JSON.load(jf)
        end
      end
    end
    tile_json_cache[tiletype]
  end

  get_wire_intent = lambda do |tiletype, wirename|
    return "GENERIC" unless ij["tiles"].key?(tiletype)
    return "GENERIC" unless ij["tiles"][tiletype].key?(wirename)
    ij["intents"][ij["tiles"][tiletype][wirename].to_s]
  end

  get_tile_type_data = lambda do |tiletype|
    unless tile_type_cache.key?(tiletype)
      td = TileData.new(tiletype)
      # Import wires and pips
      tj = read_tile_type_json.call(tiletype)
      tj["wires"].sort.each do |wire, wire_data|
        wire_id = td.wires.length
        wd = WireData.new(index: wire_id, name: wire, tied_value: nil) # FIXME: tied_value
        wd.intent = get_wire_intent.call(tiletype, wire)
        unless wire_data.nil?
          wd.resistance = wire_data["res"].to_f if wire_data.key?("res")
          wd.capacitance = wire_data["cap"].to_f if wire_data.key?("cap")
        end
        td.wires << wd
        td.wires_by_name[wire] = wd
      end
      tj["pips"].sort.each do |pip, pipdata|
        # FIXME: pip/wire delays
        pip_id = td.pips.length
        pd = PIPData.new(
          index: pip_id,
          from_wire: td.wires_by_name[pipdata["src_wire"]].index,
          to_wire: td.wires_by_name[pipdata["dst_wire"]].index,
          is_bidi: !pipdata["is_directional"].to_i.zero? ? false : true,
          is_route_thru: !pipdata["is_pseudo"].to_i.zero?
        )
        if pipdata.key?("is_pass_transistor")
          pd.is_buffered = !pipdata["is_pass_transistor"].to_i.zero? ? false : true
        end
        if pipdata.key?("src_to_dst")
          s2d = pipdata["src_to_dst"]
          if s2d.key?("delay") && !s2d["delay"].nil?
            pd.min_delay = [s2d["delay"][0].to_f, s2d["delay"][1].to_f].min
            pd.max_delay = [s2d["delay"][2].to_f, s2d["delay"][3].to_f].max
          end
          if s2d.key?("res") && !s2d["res"].nil?
            pd.resistance = s2d["res"].to_f
          end
          if s2d.key?("in_cap") && !s2d["in_cap"].nil?
            pd.capacitance = s2d["in_cap"].to_f
          end
        end
        td.pips << pd
      end
      tj["sites"].each do |sitedata|
        rel_xy = parse_xy.call(sitedata["name"])
        sitetype = sitedata["type"]
        sitedata["site_pins"].sort.each do |sitepin, pindata|
          if pindata.nil?
            tspd = TileSitePinData.new(nil)
          else
            pinwire = td.wires_by_name[pindata["wire"]].index
            tspd = TileSitePinData.new(pinwire)
            if pindata.key?("delay")
              tspd.min_delay = [pindata["delay"][0].to_f, pindata["delay"][1].to_f].min
              tspd.max_delay = [pindata["delay"][2].to_f, pindata["delay"][3].to_f].max
            end
            tspd.resistance = pindata["res"].to_f if pindata.key?("res")
            tspd.capacitance = pindata["cap"].to_f if pindata.key?("cap")
          end
          td.sitepin_data[[sitetype, rel_xy, sitepin]] = tspd
        end
      end
      sdf_path = "#{prjxray_root}/timings/#{tiletype}.sdf"
      td.cell_timing = parse_sdf_file(sdf_path) if File.exist?(sdf_path)

      tile_type_cache[tiletype] = td
    end
    tile_type_cache[tiletype]
  end

  d = Device.new(fabricname)

  # Load intent JSON
  ij = File.open("#{metadata_root}/wire_intents.json", "r") { |ijf| JSON.load(ijf) }
  tgj = File.open("#{prjxray_root}/#{fabricname}/tilegrid.json") { |gf| JSON.load(gf) }
  tgj.sort.each do |tile, tiledata|
    x = tiledata["grid_x"].to_i
    y = tiledata["grid_y"].to_i
    d.width = [d.width, x + 1].max
    d.height = [d.height, y + 1].max
    tiletype = tiledata["type"]
    t = Tile.new(x, y, tile, get_tile_type_data.call(tiletype), [-1, -1], [])
    tiledata["sites"].sort.each_with_index do |(site, sitetype), idx|
      si = Site.new(t, site, idx, parse_xy.call(site), get_site_type_data.call(sitetype))
      t.site_insts << si
      d.sites_by_name[site] = si
    end
    d.tiles_by_name[tile] = t
    d.tiles_by_xy[[x, y]] = t
    d.tiles << t
  end

  # Resolve interconnect tile coordinates
  d.tiles.each do |t|
    0.upto(29) do |delta|
      break if t.interconn_xy != [-1, -1] # found, done
      [-1, +1].each do |direction|
        nxy = [t.x + direction * delta, t.y]
        next unless d.tiles_by_xy.key?(nxy)
        next unless ["INT", "INT_L", "INT_R"].include?(d.tiles_by_xy[nxy].tile_type)
        t.interconn_xy = nxy
        break
      end
    end
  end

  # Read package pins
  Dir.each_child(prjxray_root) do |entry_name|
    entry_path = File.join(prjxray_root, entry_name)
    next unless File.directory?(entry_path)
    next unless entry_name.start_with?(fabricname)
    device_postfix = entry_name[fabricname.length..]
    next if device_postfix.empty?
    package_name = device_postfix.split("-")[0]
    next if d.packages.key?(package_name) # already seen in a different speed grade
    File.open("#{prjxray_root}/#{entry_name}/package_pins.csv") do |ppf|
      pkg = Package.new(package_name)
      ppf.each_line do |line|
        sl = line.strip.split(",")
        next if sl.length < 3
        next if sl[2] == "site" # header
        pkg.pin_map[sl[0]] = sl[2]
      end
      d.packages[package_name] = pkg
    end
  end

  File.open("#{prjxray_root}/#{fabricname}/tileconn.json", "r") do |tcf|
    apply_tileconn(tcf, d)
  end
  d
end

if __FILE__ == $PROGRAM_NAME
  import_device(*ARGV)
end
