require 'optparse'
require_relative '../../himbaechel_dbgen/chip'
require_relative '../../himbaechel_dbgen/bba'

# Grid size including IOBs at edges
X = 100
Y = 100
# LUT input count
K = 4
# SLICEs per tile
N = 8
# number of local wires
Wl = N * (K + 1) + 16
# 1/Fc for bel input wire pips; local wire pips and neighbour pips
Si = 6
Sq = 6
Sl = 1

DIRS = [ # name, dx, dy
  ["N",  0, -1],
  ["NE", 1, -1],
  ["E",  1,  0],
  ["SE", 1,  1],
  ["S",  0,  1],
  ["SW", -1, 1],
  ["W",  -1, 0],
  ["NW", -1, -1]
]

def create_switch_matrix(tt, inputs, outputs)
  # FIXME: terrible routing matrix, just for a toy example...
  # constant wires
  tt.create_wire("GND", "GND", const_value: "GND")
  tt.create_wire("VCC", "VCC", const_value: "VCC")
  # switch wires
  Wl.times do |i|
    tt.create_wire("SWITCH#{i}", "SWITCH")
  end
  # neighbor wires
  Wl.times do |i|
    DIRS.each do |d, dx, dy|
      tt.create_wire("#{d}#{i}", "NEIGH_#{d}")
    end
  end
  # input pips
  inputs.each_with_index do |w, i|
    (i % Si).step(Wl - 1, Si) do |j|
      tt.create_pip("SWITCH#{j}", w, timing_class: "SWINPUT")
    end
  end
  # output pips
  outputs.each_with_index do |w, i|
    (i % Sq).step(Wl - 1, Sq) do |j|
      tt.create_pip(w, "SWITCH#{j}", timing_class: "SWINPUT")
    end
  end
  # constant pips
  Wl.times do |i|
    tt.create_pip("GND", "SWITCH#{i}")
    tt.create_pip("VCC", "SWITCH#{i}")
  end
  # neighbour local pips
  Wl.times do |i|
    DIRS.each_with_index do |(d, dx, dy), j|
      tt.create_pip("#{d}#{(i + j) % Wl}", "SWITCH#{i}", timing_class: "SWNEIGH")
    end
  end
  # clock "ladder"
  unless tt.has_wire("CLK")
    tt.create_wire("CLK", "TILE_CLK")
  end
  tt.create_wire("CLK_PREV", "CLK_ROUTE")
  tt.create_pip("CLK_PREV", "CLK")

  tt.create_group("SWITCHBOX", "SWITCHBOX")
end

def create_logic_tiletype(chip)
  tt = chip.create_tile_type("LOGIC")
  # setup wires
  inputs = []
  outputs = []
  N.times do |i|
    K.times do |j|
      inputs << "L#{i}_I#{j}"
      tt.create_wire("L#{i}_I#{j}", "LUT_INPUT")
    end
    tt.create_wire("L#{i}_D", "FF_DATA")
    tt.create_wire("L#{i}_O", "LUT_OUT")
    tt.create_wire("L#{i}_Q", "FF_OUT")
    outputs += ["L#{i}_O", "L#{i}_Q"]
  end
  tt.create_wire("CLK", "TILE_CLK")
  # create logic cells
  N.times do |i|
    # LUT
    lut = tt.create_bel("L#{i}_LUT", "LUT4", z: (i * 2 + 0))
    K.times do |j|
      tt.add_bel_pin(lut, "I[#{j}]", "L#{i}_I#{j}", PinType::INPUT)
    end
    tt.add_bel_pin(lut, "F", "L#{i}_O", PinType::OUTPUT)
    # FF data can come from LUT output or LUT I3
    tt.create_pip("L#{i}_O", "L#{i}_D")
    tt.create_pip("L#{i}_I#{K - 1}", "L#{i}_D")
    # FF
    ff = tt.create_bel("L#{i}_FF", "DFF", z: (i * 2 + 1))
    tt.add_bel_pin(ff, "D", "L#{i}_D", PinType::INPUT)
    tt.add_bel_pin(ff, "CLK", "CLK", PinType::INPUT)
    tt.add_bel_pin(ff, "Q", "L#{i}_Q", PinType::OUTPUT)
  end
  create_switch_matrix(tt, inputs, outputs)
  tt
end

N_IO = 2

def create_io_tiletype(chip)
  tt = chip.create_tile_type("IO")
  # setup wires
  inputs = []
  outputs = []
  N_IO.times do |i|
    tt.create_wire("IO#{i}_T", "IO_T")
    tt.create_wire("IO#{i}_I", "IO_I")
    tt.create_wire("IO#{i}_O", "IO_O")
    tt.create_wire("IO#{i}_PAD", "IO_PAD")
    inputs += ["IO#{i}_T", "IO#{i}_I"]
    outputs += ["IO#{i}_O"]
  end
  tt.create_wire("CLK", "TILE_CLK")
  N_IO.times do |i|
    io = tt.create_bel("IO#{i}", "IOB", z: i)
    tt.add_bel_pin(io, "I", "IO#{i}_I", PinType::INPUT)
    tt.add_bel_pin(io, "T", "IO#{i}_T", PinType::INPUT)
    tt.add_bel_pin(io, "O", "IO#{i}_O", PinType::OUTPUT)
    tt.add_bel_pin(io, "PAD", "IO#{i}_PAD", PinType::INOUT)
  end
  # Actually used in top left IO only
  tt.create_wire("GCLK_OUT", "GCLK")
  tt.create_pip("IO0_O", "GCLK_OUT")
  create_switch_matrix(tt, inputs, outputs)
  tt
end

def create_bram_tiletype(chip)
  aw = 9
  dw = 16

  tt = chip.create_tile_type("BRAM")
  inputs = (0...aw).map { |i| "RAM_WA#{i}" }
  inputs += (0...aw).map { |i| "RAM_RA#{i}" }
  inputs += (0...(dw / 8)).map { |i| "RAM_WE#{i}" }
  inputs += (0...dw).map { |i| "RAM_DI#{i}" }
  outputs = (0...dw).map { |i| "RAM_DO#{i}" }
  inputs.each { |w| tt.create_wire(w, "RAM_IN") }
  outputs.each { |w| tt.create_wire(w, "RAM_OUT") }
  tt.create_wire("CLK", "TILE_CLK")
  ram = tt.create_bel("RAM", "BRAM_#{2**aw}X#{dw}", z: 0)
  tt.add_bel_pin(ram, "CLK", "CLK", PinType::INPUT)
  aw.times do |i|
    tt.add_bel_pin(ram, "WA[#{i}]", "RAM_WA#{i}", PinType::INPUT)
    tt.add_bel_pin(ram, "RA[#{i}]", "RAM_RA#{i}", PinType::INPUT)
  end
  (dw / 8).times do |i|
    tt.add_bel_pin(ram, "WE[#{i}]", "RAM_WE#{i}", PinType::INPUT)
  end
  dw.times do |i|
    tt.add_bel_pin(ram, "DI[#{i}]", "RAM_DI#{i}", PinType::INPUT)
    tt.add_bel_pin(ram, "DO[#{i}]", "RAM_DO#{i}", PinType::OUTPUT)
  end
  create_switch_matrix(tt, inputs, outputs)
  tt
end

def create_corner_tiletype(ch)
  tt = ch.create_tile_type("NULL")
  tt.create_wire("CLK", "TILE_CLK")
  tt.create_wire("CLK_PREV", "CLK_ROUTE")
  tt.create_pip("CLK_PREV", "CLK")

  tt.create_wire("GND", "GND", const_value: "GND")
  tt.create_wire("VCC", "VCC", const_value: "VCC")

  gnd = tt.create_bel("GND_DRV", "GND_DRV", z: 0)
  tt.add_bel_pin(gnd, "GND", "GND", PinType::OUTPUT)
  vcc = tt.create_bel("VCC_DRV", "VCC_DRV", z: 1)
  tt.add_bel_pin(vcc, "VCC", "VCC", PinType::OUTPUT)

  tt
end

def is_corner(x, y)
  ((x == 0) || (x == (X - 1))) && ((y == 0) || (y == (Y - 1)))
end

def create_nodes(ch)
  Y.times do |y|
    # puts "generating nodes for row #{y}"
    X.times do |x|
      unless is_corner(x, y)
        # connect up actual neighbours
        local_nodes = Array.new(Wl) { |i| [NodeWire.new(x, y, "SWITCH#{i}")] }
        DIRS.each do |d, dx, dy|
          x1 = x - dx
          y1 = y - dy
          next if x1 < 0 || x1 >= X || y1 < 0 || y1 >= Y || is_corner(x1, y1)
          Wl.times do |i|
            local_nodes[i] << NodeWire.new(x1, y1, "#{d}#{i}")
          end
        end
        local_nodes.each { |n| ch.add_node(n) }
      end
      # connect up clock ladder (not intended to be a sensible clock structure)
      if y != 1 # special case where the node has 3 wires
        if y == 0
          if x == 0
            # clock source: IO
            clk_node = [NodeWire.new(1, 0, "GCLK_OUT")]
          else
            # clock source: left
            clk_node = [NodeWire.new(x - 1, y, "CLK")]
          end
        else
          # clock source: above
          clk_node = [NodeWire.new(x, y - 1, "CLK")]
        end
        clk_node << NodeWire.new(x, y, "CLK_PREV")
        if y == 0
          clk_node << NodeWire.new(x, y + 1, "CLK_PREV")
        end
        ch.add_node(clk_node)
      end
    end
  end
end

def set_timings(ch)
  speed = "DEFAULT"
  tmg = ch.set_speed_grades([speed])
  # --- Routing Delays ---
  # Notes: A simpler timing model could just use intrinsic delay and ignore R and Cs.
  # R and C values don't have to be physically realistic, just in agreement with themselves to provide
  # a meaningful scaling of delay with fanout. Units are subject to change.
  tmg.set_pip_class(grade: speed, name: "SWINPUT",
    delay: TimingValue.new(80),    # 80ps intrinstic delay
    in_cap: TimingValue.new(5000), # 5pF
    out_res: TimingValue.new(1000) # 1ohm
  )
  tmg.set_pip_class(grade: speed, name: "SWOUTPUT",
    delay: TimingValue.new(100),  # 100ps intrinstic delay
    in_cap: TimingValue.new(5000), # 5pF
    out_res: TimingValue.new(800)  # 0.8ohm
  )
  tmg.set_pip_class(grade: speed, name: "SWNEIGH",
    delay: TimingValue.new(120),   # 120ps intrinstic delay
    in_cap: TimingValue.new(7000), # 7pF
    out_res: TimingValue.new(1200) # 1.2ohm
  )
  # TODO: also support node/wire delays and add an example of them

  # --- Cell delays ---
  lut = ch.timing.add_cell_variant(speed, "LUT4")
  K.times do |j|
    lut.add_comb_arc("I[#{j}]", "F", TimingValue.new(150 + j * 15))
  end
  dff = ch.timing.add_cell_variant(speed, "DFF")
  dff.add_setup_hold("CLK", "D", ClockEdge::RISING, TimingValue.new(150), TimingValue.new(25))
  dff.add_clock_out("CLK", "Q", ClockEdge::RISING, TimingValue.new(200))
end

def main
  ch = Chip.new("example", "EX1", X, Y)
  # Init constant ids
  ch.strs.read_constids(File.join(File.dirname(__FILE__), "constids.inc"))
  ch.read_gfxids(File.join(File.dirname(__FILE__), "gfxids.inc"))
  _logic = create_logic_tiletype(ch)
  _io    = create_io_tiletype(ch)
  _bram  = create_bram_tiletype(ch)
  _null  = create_corner_tiletype(ch)
  # Setup tile grid
  X.times do |x|
    Y.times do |y|
      if x == 0 || x == X - 1 # left/right side IO
        if y == 0 || y == Y - 1 # corner
          ch.set_tile_type(x, y, "NULL")
        else
          ch.set_tile_type(x, y, "IO")
        end
      elsif y == 0 || y == Y - 1 # top/bottom side IO
        ch.set_tile_type(x, y, "IO")
      elsif (y % 15) == 7 # BRAM
        ch.set_tile_type(x, y, "BRAM")
      else
        ch.set_tile_type(x, y, "LOGIC")
      end
    end
  end
  # Create nodes between tiles
  create_nodes(ch)
  set_timings(ch)
  ch.write_bba(ARGV[0])
end

main
