#!/usr/bin/env ruby

require 'optparse'
require 'set'

def main
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: chipdb.rb [options] filename"
    opts.on("-p", "--constids PATH", "path to constids.inc") { |v| options[:constids] = v }
    opts.on("-g", "--gfxh PATH", "path to gfx.h") { |v| options[:gfxh] = v }
    opts.on("--fast PATH", "path to timing data for fast part") { |v| options[:fast] = v }
    opts.on("--slow PATH", "path to timing data for slow part") { |v| options[:slow] = v }
  end.parse!

  filename = ARGV[0]
  raise "filename argument required" unless filename

  $dev_name   = nil
  $dev_width  = nil
  $dev_height = nil
  $num_wires  = nil

  $tiles = {}

  $wire_uphill   = {}
  $wire_downhill = {}
  $pip_xy        = {}

  $bel_name  = []
  $bel_type  = []
  $bel_pos   = []
  $bel_wires = []

  $switches = []
  $ierens   = []

  $extra_cells       = {}
  $extra_cell_config = {}
  $packages          = []
  $glbinfo           = Hash[(0...8).map { |i| [i, {}] }]

  $wire_belports = {}

  $wire_names   = {}
  $wire_names_r = {}
  $wire_xy      = {}

  $cbit_re = /B(\d+)\[(\d+)\]/

  $constids  = {}
  $tiletypes = {}
  $wiretypes = {}

  $gfx_wire_ids   = {}
  $gfx_wire_names = []
  $wire_segments  = {}

  $fast_timings = nil
  $slow_timings = nil

  # Read constids
  File.open(options[:constids]) do |f|
    f.each_line do |line|
      next if line.start_with?("//")
      line = line.gsub("(", " ").gsub(")", " ")
      line = line.split
      next if line.length == 0
      raise "expected 2 tokens" unless line.length == 2
      raise "expected X" unless line[0] == "X"
      idx = $constids.length + 1
      $constids[line[1]] = idx
    end
  end

  $constids["PLL"]         = $constids["ICESTORM_PLL"]
  $constids["WARMBOOT"]    = $constids["SB_WARMBOOT"]
  $constids["MAC16"]       = $constids["ICESTORM_DSP"]
  $constids["HFOSC"]       = $constids["ICESTORM_HFOSC"]
  $constids["LFOSC"]       = $constids["ICESTORM_LFOSC"]
  $constids["I2C"]         = $constids["SB_I2C"]
  $constids["SPI"]         = $constids["SB_SPI"]
  $constids["LEDDA_IP"]    = $constids["SB_LEDDA_IP"]
  $constids["RGBA_DRV"]    = $constids["SB_RGBA_DRV"]
  $constids["SPRAM"]       = $constids["ICESTORM_SPRAM"]
  $constids["LED_DRV_CUR"] = $constids["SB_LED_DRV_CUR"]
  $constids["RGB_DRV"]     = $constids["SB_RGB_DRV"]

  # Read gfx.h
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
        idx = $gfx_wire_ids.length
        name = line.strip.sub(/,$/, "")
        $gfx_wire_ids[name] = idx
        $gfx_wire_names << name
      end
    end
  end

  # GFX aliases for RAM tiles
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_0", "TILE_WIRE_RAM_RADDR_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_1", "TILE_WIRE_RAM_RADDR_1")
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_2", "TILE_WIRE_RAM_RADDR_2")
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_3", "TILE_WIRE_RAM_RADDR_3")

  gfx_wire_alias("TILE_WIRE_LUTFF_1_IN_0", "TILE_WIRE_RAM_RADDR_4")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_IN_1", "TILE_WIRE_RAM_RADDR_5")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_IN_2", "TILE_WIRE_RAM_RADDR_6")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_IN_3", "TILE_WIRE_RAM_RADDR_7")

  gfx_wire_alias("TILE_WIRE_LUTFF_2_IN_0", "TILE_WIRE_RAM_RADDR_8")
  gfx_wire_alias("TILE_WIRE_LUTFF_2_IN_1", "TILE_WIRE_RAM_RADDR_9")
  gfx_wire_alias("TILE_WIRE_LUTFF_2_IN_2", "TILE_WIRE_RAM_RADDR_10")

  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_0", "TILE_WIRE_RAM_WADDR_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_1", "TILE_WIRE_RAM_WADDR_1")
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_2", "TILE_WIRE_RAM_WADDR_2")
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_3", "TILE_WIRE_RAM_WADDR_3")

  gfx_wire_alias("TILE_WIRE_LUTFF_1_IN_0", "TILE_WIRE_RAM_WADDR_4")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_IN_1", "TILE_WIRE_RAM_WADDR_5")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_IN_2", "TILE_WIRE_RAM_WADDR_6")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_IN_3", "TILE_WIRE_RAM_WADDR_7")

  gfx_wire_alias("TILE_WIRE_LUTFF_2_IN_0", "TILE_WIRE_RAM_WADDR_8")
  gfx_wire_alias("TILE_WIRE_LUTFF_2_IN_1", "TILE_WIRE_RAM_WADDR_9")
  gfx_wire_alias("TILE_WIRE_LUTFF_2_IN_2", "TILE_WIRE_RAM_WADDR_10")

  gfx_wire_alias("TILE_WIRE_LUTFF_3_IN_0", "TILE_WIRE_RAM_MASK_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_3_IN_1", "TILE_WIRE_RAM_MASK_1")
  gfx_wire_alias("TILE_WIRE_LUTFF_3_IN_2", "TILE_WIRE_RAM_MASK_2")
  gfx_wire_alias("TILE_WIRE_LUTFF_3_IN_3", "TILE_WIRE_RAM_MASK_3")

  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_0", "TILE_WIRE_RAM_MASK_4")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_1", "TILE_WIRE_RAM_MASK_5")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_2", "TILE_WIRE_RAM_MASK_6")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_3", "TILE_WIRE_RAM_MASK_7")

  gfx_wire_alias("TILE_WIRE_LUTFF_3_IN_0", "TILE_WIRE_RAM_MASK_8")
  gfx_wire_alias("TILE_WIRE_LUTFF_3_IN_1", "TILE_WIRE_RAM_MASK_9")
  gfx_wire_alias("TILE_WIRE_LUTFF_3_IN_2", "TILE_WIRE_RAM_MASK_10")
  gfx_wire_alias("TILE_WIRE_LUTFF_3_IN_3", "TILE_WIRE_RAM_MASK_11")

  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_0", "TILE_WIRE_RAM_MASK_12")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_1", "TILE_WIRE_RAM_MASK_13")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_2", "TILE_WIRE_RAM_MASK_14")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_3", "TILE_WIRE_RAM_MASK_15")

  gfx_wire_alias("TILE_WIRE_LUTFF_5_IN_0", "TILE_WIRE_RAM_WDATA_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_IN_1", "TILE_WIRE_RAM_WDATA_1")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_IN_2", "TILE_WIRE_RAM_WDATA_2")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_IN_3", "TILE_WIRE_RAM_WDATA_3")

  gfx_wire_alias("TILE_WIRE_LUTFF_6_IN_0", "TILE_WIRE_RAM_WDATA_4")
  gfx_wire_alias("TILE_WIRE_LUTFF_6_IN_1", "TILE_WIRE_RAM_WDATA_5")
  gfx_wire_alias("TILE_WIRE_LUTFF_6_IN_2", "TILE_WIRE_RAM_WDATA_6")
  gfx_wire_alias("TILE_WIRE_LUTFF_6_IN_3", "TILE_WIRE_RAM_WDATA_7")

  gfx_wire_alias("TILE_WIRE_LUTFF_5_IN_0", "TILE_WIRE_RAM_WDATA_8")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_IN_1", "TILE_WIRE_RAM_WDATA_9")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_IN_2", "TILE_WIRE_RAM_WDATA_10")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_IN_3", "TILE_WIRE_RAM_WDATA_11")

  gfx_wire_alias("TILE_WIRE_LUTFF_6_IN_0", "TILE_WIRE_RAM_WDATA_12")
  gfx_wire_alias("TILE_WIRE_LUTFF_6_IN_1", "TILE_WIRE_RAM_WDATA_13")
  gfx_wire_alias("TILE_WIRE_LUTFF_6_IN_2", "TILE_WIRE_RAM_WDATA_14")
  gfx_wire_alias("TILE_WIRE_LUTFF_6_IN_3", "TILE_WIRE_RAM_WDATA_15")

  gfx_wire_alias("TILE_WIRE_LUTFF_0_OUT", "TILE_WIRE_RAM_RDATA_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_OUT", "TILE_WIRE_RAM_RDATA_1")
  gfx_wire_alias("TILE_WIRE_LUTFF_2_OUT", "TILE_WIRE_RAM_RDATA_2")
  gfx_wire_alias("TILE_WIRE_LUTFF_3_OUT", "TILE_WIRE_RAM_RDATA_3")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_OUT", "TILE_WIRE_RAM_RDATA_4")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_OUT", "TILE_WIRE_RAM_RDATA_5")
  gfx_wire_alias("TILE_WIRE_LUTFF_6_OUT", "TILE_WIRE_RAM_RDATA_6")
  gfx_wire_alias("TILE_WIRE_LUTFF_7_OUT", "TILE_WIRE_RAM_RDATA_7")

  gfx_wire_alias("TILE_WIRE_LUTFF_0_OUT", "TILE_WIRE_RAM_RDATA_8")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_OUT", "TILE_WIRE_RAM_RDATA_9")
  gfx_wire_alias("TILE_WIRE_LUTFF_2_OUT", "TILE_WIRE_RAM_RDATA_10")
  gfx_wire_alias("TILE_WIRE_LUTFF_3_OUT", "TILE_WIRE_RAM_RDATA_11")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_OUT", "TILE_WIRE_RAM_RDATA_12")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_OUT", "TILE_WIRE_RAM_RDATA_13")
  gfx_wire_alias("TILE_WIRE_LUTFF_6_OUT", "TILE_WIRE_RAM_RDATA_14")
  gfx_wire_alias("TILE_WIRE_LUTFF_7_OUT", "TILE_WIRE_RAM_RDATA_15")

  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_CEN", "TILE_WIRE_RAM_RCLKE")
  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_CEN", "TILE_WIRE_RAM_WCLKE")
  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_CLK", "TILE_WIRE_RAM_RCLK")
  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_CLK", "TILE_WIRE_RAM_WCLK")
  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_S_R", "TILE_WIRE_RAM_RE")
  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_S_R", "TILE_WIRE_RAM_WE")

  # GFX aliases for IO tiles
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_0", "TILE_WIRE_IO_0_D_OUT_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_1", "TILE_WIRE_IO_0_D_OUT_1")
  gfx_wire_alias("TILE_WIRE_LUTFF_0_IN_3", "TILE_WIRE_IO_0_OUT_ENB")

  gfx_wire_alias("TILE_WIRE_LUTFF_0_OUT", "TILE_WIRE_IO_0_D_IN_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_1_OUT", "TILE_WIRE_IO_0_D_IN_1")

  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_0", "TILE_WIRE_IO_1_D_OUT_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_1", "TILE_WIRE_IO_1_D_OUT_1")
  gfx_wire_alias("TILE_WIRE_LUTFF_4_IN_3", "TILE_WIRE_IO_1_OUT_ENB")

  gfx_wire_alias("TILE_WIRE_LUTFF_4_OUT", "TILE_WIRE_IO_1_D_IN_0")
  gfx_wire_alias("TILE_WIRE_LUTFF_5_OUT", "TILE_WIRE_IO_1_D_IN_1")

  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_CEN", "TILE_WIRE_IO_GLOBAL_CEN")
  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_CLK", "TILE_WIRE_IO_GLOBAL_INCLK")
  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_S_R", "TILE_WIRE_IO_GLOBAL_OUTCLK")

  gfx_wire_alias("TILE_WIRE_FUNC_GLOBAL_G0", "TILE_WIRE_IO_GLOBAL_LATCH")

  "BNL BNR BOT LFT RGT TNL TNR TOP".split.each do |neigh|
    8.times do |i|
      gfx_wire_alias("TILE_WIRE_NEIGH_OP_#{neigh}_#{i}", "TILE_WIRE_LOGIC_OP_#{neigh}_#{i}")
    end
  end

  # End of GFX aliases

  $fast_timings = read_timings(options[:fast]) if options[:fast]
  $slow_timings = read_timings(options[:slow]) if options[:slow]

  $tiletypes["NONE"]  = 0
  $tiletypes["LOGIC"] = 1
  $tiletypes["IO"]    = 2
  $tiletypes["RAMB"]  = 3
  $tiletypes["RAMT"]  = 4
  $tiletypes["DSP0"]  = 5
  $tiletypes["DSP1"]  = 6
  $tiletypes["DSP2"]  = 7
  $tiletypes["DSP3"]  = 8
  $tiletypes["IPCON"] = 9

  $wiretypes["NONE"]         = 0
  $wiretypes["GLB2LOCAL"]    = 1
  $wiretypes["GLB_NETWK"]    = 2
  $wiretypes["LOCAL"]        = 3
  $wiretypes["LUTFF_IN"]     = 4
  $wiretypes["LUTFF_IN_LUT"] = 5
  $wiretypes["LUTFF_LOUT"]   = 6
  $wiretypes["LUTFF_OUT"]    = 7
  $wiretypes["LUTFF_COUT"]   = 8
  $wiretypes["LUTFF_GLOBAL"] = 9
  $wiretypes["CARRY_IN_MUX"] = 10
  $wiretypes["SP4_V"]        = 11
  $wiretypes["SP4_H"]        = 12
  $wiretypes["SP12_V"]       = 13
  $wiretypes["SP12_H"]       = 14

  # Read chipdb file
  $num_tile_types = nil
  $tile_sizes     = nil
  $tile_bits      = nil

  File.open(filename, "r") do |f|
    mode = nil

    f.each_line do |line|
      line = line.split

      next if line.length == 0 || line[0] == "#"

      if line[0] == ".device"
        $dev_name = line[1]
        init_tiletypes($dev_name)
        $dev_width  = line[2].to_i
        $dev_height = line[3].to_i
        $num_wires  = line[4].to_i
        next
      end

      if line[0] == ".net"
        mode = ["net", line[1].to_i]
        next
      end

      if line[0] == ".buffer"
        mode = ["buffer", line[3].to_i, line[1].to_i, line[2].to_i]
        $switches << [line[1].to_i, line[2].to_i, line[4..], -1]
        next
      end

      if line[0] == ".routing"
        mode = ["routing", line[3].to_i, line[1].to_i, line[2].to_i]
        $switches << [line[1].to_i, line[2].to_i, line[4..], -1]
        next
      end

      if line[0] == ".io_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "io"
        mode = nil
        next
      end

      if line[0] == ".logic_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "logic"
        mode = nil
        next
      end

      if line[0] == ".ramb_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "ramb"
        mode = nil
        next
      end

      if line[0] == ".ramt_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "ramt"
        mode = nil
        next
      end

      if line[0] == ".dsp0_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "dsp0"
        mode = nil
        next
      end

      if line[0] == ".dsp1_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "dsp1"
        mode = nil
        next
      end

      if line[0] == ".dsp2_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "dsp2"
        mode = nil
        next
      end

      if line[0] == ".dsp3_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "dsp3"
        mode = nil
        next
      end

      if line[0] == ".ipcon_tile"
        $tiles[[line[1].to_i, line[2].to_i]] = "ipcon"
        mode = nil
        next
      end

      if line[0] == ".logic_tile_bits"
        mode = ["bits", 1]
        $tile_sizes[1] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".io_tile_bits"
        mode = ["bits", 2]
        $tile_sizes[2] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".ramb_tile_bits"
        mode = ["bits", 3]
        $tile_sizes[3] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".ramt_tile_bits"
        mode = ["bits", 4]
        $tile_sizes[4] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".dsp0_tile_bits"
        mode = ["bits", 5]
        $tile_sizes[5] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".dsp1_tile_bits"
        mode = ["bits", 6]
        $tile_sizes[6] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".dsp2_tile_bits"
        mode = ["bits", 7]
        $tile_sizes[7] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".dsp3_tile_bits"
        mode = ["bits", 8]
        $tile_sizes[8] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".ipcon_tile_bits"
        mode = ["bits", 9]
        $tile_sizes[9] = [line[1].to_i, line[2].to_i]
        next
      end

      if line[0] == ".ieren"
        mode = ["ieren"]
        next
      end

      if line[0] == ".pins"
        mode = ["pins", line[1]]
        $packages << [line[1], []]
        next
      end

      if line[0] == ".extra_cell"
        if line.length >= 5
          mode = ["extra_cell", [line[4], line[1].to_i, line[2].to_i, line[3].to_i]]
        elsif line[3] == "WARMBOOT"
          mode = ["extra_cell", [line[3], line[1].to_i, line[2].to_i, 0]]
        elsif line[3] == "PLL"
          mode = ["extra_cell", [line[3], line[1].to_i, line[2].to_i, 3]]
        else
          raise "unexpected extra_cell line"
        end
        $extra_cells[mode[1]] = []
        next
      end

      if line[0] == ".gbufin"
        mode = ["gbufin"]
        next
      end

      if line[0] == ".gbufpin"
        mode = ["gbufpin"]
        next
      end

      if line[0] == ".extra_bits"
        mode = ["extra_bits"]
        next
      end

      if line[0][0] == "." || mode.nil?
        mode = nil
        next
      end

      if mode[0] == "net"
        wname = [line[0].to_i, line[1].to_i, line[2]]
        $wire_names[wname] = mode[1]
        if !$wire_names_r.key?(mode[1]) || cmp_wire_names(wname, $wire_names_r[mode[1]])
          $wire_names_r[mode[1]] = wname
        end
        $wire_xy[mode[1]] ||= []
        $wire_xy[mode[1]] << wname
        $wire_segments[mode[1]] ||= {}
        tile_wire_key = "TILE_WIRE_" + wname[2].upcase.gsub("/", "_")
        if $gfx_wire_ids.key?(tile_wire_key)
          xy_key = [wname[0], wname[1]]
          $wire_segments[mode[1]][xy_key] ||= []
          $wire_segments[mode[1]][xy_key] << wname[2]
        end
        next
      end

      if mode[0] == "buffer" || mode[0] == "routing"
        wire_a = line[1].to_i
        wire_b = mode[1]
        $wire_downhill[wire_a] ||= Set.new
        $wire_uphill[wire_b]   ||= Set.new
        $wire_downhill[wire_a].add(wire_b)
        $wire_uphill[wire_b].add(wire_a)
        $pip_xy[[wire_a, wire_b]] = [mode[2], mode[3], line[0].to_i(2), $switches.length - 1, 0]
        next
      end

      if mode[0] == "bits"
        name = line[0]
        bits = []
        line[1..].each do |b|
          m = $cbit_re.match(b)
          raise "cbit_re match failed for #{b}" unless m
          bits << [m[1].to_i, m[2].to_i]
        end
        $tile_bits[mode[1]] << [name, bits]
        next
      end

      if mode[0] == "ieren"
        $ierens << line.map(&:to_i)
        next
      end

      if mode[0] == "pins"
        $packages[-1][1] << [line[0], line[1].to_i, line[2].to_i, line[3].to_i]
        next
      end

      if mode[0] == "extra_cell"
        if line[0] == "LOCKED"
          line[1..].each do |pkg|
            $extra_cells[mode[1]] << [("LOCKED_" + pkg), [0, 0, "LOCKED"]]
          end
        else
          $extra_cells[mode[1]] << [line[0], [line[1].to_i, line[2].to_i, line[3]]]
        end
        next
      end

      if mode[0] == "gbufin"
        idx = line[2].to_i
        $glbinfo[idx]['gb_x'] = line[0].to_i
        $glbinfo[idx]['gb_y'] = line[1].to_i
        next
      end

      if mode[0] == "gbufpin"
        idx = line[3].to_i
        $glbinfo[idx]['pi_gb_x']   = line[0].to_i
        $glbinfo[idx]['pi_gb_y']   = line[1].to_i
        $glbinfo[idx]['pi_gb_pio'] = line[2].to_i
        next
      end

      if mode[0] == "extra_bits"
        if line[0].start_with?('padin_glb_netwk.')
          idx = line[0].split('.')[1].to_i
          $glbinfo[idx]['pi_eb_bank'] = line[1].to_i
          $glbinfo[idx]['pi_eb_x']    = line[2].to_i
          $glbinfo[idx]['pi_eb_y']    = line[3].to_i
        end
        next
      end
    end
  end

  cell_timings = {}
  tmport_to_constids = {
    "posedge:clk"  => "CLK",
    "ce"           => "CEN",
    "sr"           => "SR",
    "in0"          => "I0",
    "in1"          => "I1",
    "in2"          => "I2",
    "in3"          => "I3",
    "carryin"      => "CIN",
    "carryout"     => "COUT",
    "lcout"        => "O",
    "ltout"        => "LO",
    "posedge:RCLK" => "RCLK",
    "posedge:WCLK" => "WCLK",
    "RCLKE"        => "RCLKE",
    "RE"           => "RE",
    "WCLKE"        => "WCLKE",
    "WE"           => "WE",
    "posedge:CLOCK"             => "CLOCK",
    "posedge:SLEEP"             => "SLEEP",
    "USERSIGNALTOGLOBALBUFFER"  => "USER_SIGNAL_TO_GLOBAL_BUFFER",
    "GLOBALBUFFEROUTPUT"        => "GLOBAL_BUFFER_OUTPUT"
  }

  16.times do |i|
    tmport_to_constids["RDATA[#{i}]"]   = "RDATA_#{i}"
    tmport_to_constids["WDATA[#{i}]"]   = "WDATA_#{i}"
    tmport_to_constids["MASK[#{i}]"]    = "MASK_#{i}"
    tmport_to_constids["DATAOUT[#{i}]"] = "DATAOUT_#{i}"
  end

  11.times do |i|
    tmport_to_constids["RADDR[#{i}]"] = "RADDR_#{i}"
    tmport_to_constids["WADDR[#{i}]"] = "WADDR_#{i}"
  end

  add_cell_timingdata = lambda do |bel_type_name, timing_cell, fast_db, slow_db|
    timing_entries = []
    database = slow_db || fast_db
    database.each_key do |key|
      skey = key.split(".")
      if skey[0] == timing_cell
        if tmport_to_constids.key?(skey[1]) && tmport_to_constids.key?(skey[2])
          iport   = tmport_to_constids[skey[1]]
          oport   = tmport_to_constids[skey[2]]
          fastdel = fast_db ? fast_db[key] : 0
          slowdel = slow_db ? slow_db[key] : 0
          timing_entries << [iport, oport, fastdel, slowdel]
        end
      end
    end
    cell_timings[bel_type_name] = timing_entries
  end

  add_cell_timingdata.call("ICESTORM_LC", "LogicCell40", $fast_timings, $slow_timings)
  add_cell_timingdata.call("SB_GB", "ICE_GB", $fast_timings, $slow_timings)

  if $dev_name != "384"
    add_cell_timingdata.call("ICESTORM_RAM", "SB_RAM40_4K", $fast_timings, $slow_timings)
  end
  if $dev_name == "5k"
    add_cell_timingdata.call("SPRAM", "SB_SPRAM256KA", $fast_timings, $slow_timings)
  end

  $tiles.sort.each do |tile_xy, tile_type|
    if tile_type == "logic"
      8.times { |i| add_bel_lc(tile_xy[0], tile_xy[1], i) }
    end

    if tile_type == "io"
      2.times { |i| add_bel_io(tile_xy[0], tile_xy[1], i) }
      $glbinfo.each { |gidx, ginfo| add_bel_gb(tile_xy, ginfo['gb_x'], ginfo['gb_y'], gidx) }
    end

    if tile_type == "ramb"
      add_bel_ram(tile_xy[0], tile_xy[1])
    end

    $extra_cells.keys.sort.each do |ec|
      if ec[1] == tile_xy[0] && ec[2] == tile_xy[1]
        add_bel_ec(ec)
      end
    end
  end

  $extra_cells.keys.sort_by { |ec| [ec[1], ec[2], ec[3], ec[0]] }.each do |ec|
    if [0, $dev_width - 1].include?(ec[1]) && [0, $dev_height - 1].include?(ec[2])
      add_bel_ec(ec)
    end
  end

  bba = BinaryBlobAssembler.new
  bba.pre('#include "nextpnr.h"')
  bba.pre('#include "embed.h"')
  bba.pre('NEXTPNR_NAMESPACE_BEGIN')
  bba.post("EmbeddedFile chipdb_file_#{$dev_name}(\"ice40/chipdb-#{$dev_name}.bin\", chipdb_blob_#{$dev_name});")
  bba.post('NEXTPNR_NAMESPACE_END')
  bba.push("chipdb_blob_#{$dev_name}")
  bba.r("chip_info_#{$dev_name}", "chip_info")

  bba.l("tile_wire_names")
  $gfx_wire_names.each { |name| bba.s(name, name) }

  $bel_name.length.times do |bel|
    bba.l("bel_wires_#{bel}", "BelWirePOD")
    $bel_wires[bel].sort.each do |data|
      bba.u32(data[0], "port")
      bba.u32(data[1], "type")
      bba.u32(data[2], "wire_index")
    end
  end

  bba.l("bel_data_#{$dev_name}", "BelInfoPOD")
  $bel_name.length.times do |bel|
    bba.s($bel_name[bel][-1], "name")
    bba.u32($constids[$bel_type[bel]], "type")
    bba.r_slice("bel_wires_#{bel}", $bel_wires[bel].length, "bel_wires")
    bba.u8($bel_pos[bel][0], "x")
    bba.u8($bel_pos[bel][1], "y")
    bba.u8($bel_pos[bel][2], "z")
    bba.u8(0, "padding")
  end

  wireinfo = []
  pipinfo  = []
  pipcache = {}

  $num_wires.times do |wire|
    if $wire_uphill.key?(wire)
      pips = []
      $wire_uphill[wire].each do |src|
        unless pipcache.key?([src, wire])
          pipcache[[src, wire]] = pipinfo.length
          pi = {}
          pi["src"]          = src
          pi["dst"]          = wire
          pi["fast_delay"]   = pipdelay(src, wire, $fast_timings)
          pi["slow_delay"]   = pipdelay(src, wire, $slow_timings)
          pi["x"]            = $pip_xy[[src, wire]][0]
          pi["y"]            = $pip_xy[[src, wire]][1]
          pi["switch_mask"]  = $pip_xy[[src, wire]][2]
          pi["switch_index"] = $pip_xy[[src, wire]][3]
          pi["flags"]        = $pip_xy[[src, wire]][4]
          pipinfo << pi
        end
        pips << pipcache[[src, wire]]
      end
      num_uphill   = pips.length
      list_uphill  = "wire#{wire}_uppips"
      bba.l(list_uphill, "int32_t")
      pips.each { |p| bba.u32(p, nil) }
    else
      num_uphill  = 0
      list_uphill = nil
    end

    if $wire_downhill.key?(wire)
      pips = []
      $wire_downhill[wire].each do |dst|
        unless pipcache.key?([wire, dst])
          pipcache[[wire, dst]] = pipinfo.length
          pi = {}
          pi["src"]          = wire
          pi["dst"]          = dst
          pi["fast_delay"]   = pipdelay(wire, dst, $fast_timings)
          pi["slow_delay"]   = pipdelay(wire, dst, $slow_timings)
          pi["x"]            = $pip_xy[[wire, dst]][0]
          pi["y"]            = $pip_xy[[wire, dst]][1]
          pi["switch_mask"]  = $pip_xy[[wire, dst]][2]
          pi["switch_index"] = $pip_xy[[wire, dst]][3]
          pi["flags"]        = $pip_xy[[wire, dst]][4]
          pipinfo << pi
        end
        pips << pipcache[[wire, dst]]
      end
      num_downhill   = pips.length
      list_downhill  = "wire#{wire}_downpips"
      bba.l(list_downhill, "int32_t")
      pips.each { |p| bba.u32(p, nil) }
    else
      num_downhill  = 0
      list_downhill = nil
    end

    if $wire_belports.key?(wire)
      num_bel_pins = $wire_belports[wire].length
      bba.l("wire#{wire}_bels", "BelPortPOD")
      $wire_belports[wire].sort.each do |belport|
        bba.u32(belport[0], "bel_index")
        bba.u32($constids[belport[1]], "port")
      end
    else
      num_bel_pins = 0
    end

    info = {}
    info["name"]   = $wire_names_r[wire][2]
    info["name_x"] = $wire_names_r[wire][0]
    info["name_y"] = $wire_names_r[wire][1]

    info["num_uphill"]   = num_uphill
    info["list_uphill"]  = list_uphill
    info["num_downhill"] = num_downhill
    info["list_downhill"] = list_downhill
    info["num_bel_pins"]  = num_bel_pins
    info["list_bel_pins"] = num_bel_pins > 0 ? "wire#{wire}_bels" : nil

    pos_xy = nil
    first  = nil

    if $wire_xy.key?(wire)
      $wire_xy[wire].each do |x, y, n|
        norm_xy = norm_wire_xy(x, y, n)
        next if norm_xy.nil?
        if pos_xy.nil?
          pos_xy = norm_xy
          first  = [x, y, n]
        elsif pos_xy != norm_xy
          $stderr.puts "Conflicting positions for wire #{info["name"]}: (#{first[0]}, #{first[1]}, #{first[2]}) -> (#{pos_xy[0]}, #{pos_xy[1]}), (#{x}, #{y}, #{n}) -> (#{norm_xy[0]}, #{norm_xy[1]})"
          raise "conflicting wire positions"
        end
      end
    end

    if pos_xy.nil?
      info["x"] = $wire_names_r[wire][0]
      info["y"] = $wire_names_r[wire][1]
    else
      info["x"] = pos_xy[0]
      info["y"] = pos_xy[1]
    end

    wireinfo << info
  end

  packageinfo = []

  $packages.each do |package|
    name, pins = package
    safename   = name.gsub(/[^A-Za-z0-9]/, "_")
    pins_info  = []
    pins.each do |pin|
      pinname, x, y, z = pin
      pin_bel = [x, y, "io#{z}"]
      bel_idx = $bel_name.index(pin_bel)
      pins_info << [pinname, bel_idx]
    end
    bba.l("package_#{safename}_pins", "PackagePinPOD")
    pins_info.each do |pi|
      bba.s(pi[0], "name")
      bba.u32(pi[1], "bel_index")
    end
    packageinfo << [name, pins_info.length, "package_#{safename}_pins"]
  end

  tilegrid = []
  $dev_height.times do |y|
    $dev_width.times do |x|
      if $tiles.key?([x, y])
        tilegrid << $tiles[[x, y]].upcase
      else
        tilegrid << "NONE"
      end
    end
  end

  tileinfo = []
  $num_tile_types.times do |t|
    centries_info = []
    $tile_bits[t].each do |cb|
      name, bits = cb
      safename = name.gsub(/[^A-Za-z0-9]/, "_")
      bba.l("tile#{t}_#{safename}_bits", "ConfigBitPOD")
      bits.each do |row, col|
        bba.u8(row, "row")
        bba.u8(col, "col")
      end
      if bits.length == 0
        bba.u32(0, "padding")
      elsif bits.length % 2 == 1
        bba.u16(0, "padding")
      end
      centries_info << [name, bits.length, t, safename]
    end
    bba.l("tile#{t}_config", "ConfigEntryPOD")
    centries_info.each do |name, num_bits, t_idx, safename|
      bba.s(name, "name")
      bba.r_slice("tile#{t_idx}_#{safename}_bits", num_bits, "num_bits")
    end
    if centries_info.length == 0
      bba.u32(0, "padding")
    end
    ti = {}
    ti["cols"]        = $tile_sizes[t][0]
    ti["rows"]        = $tile_sizes[t][1]
    ti["num_entries"] = centries_info.length
    ti["entries"]     = "tile#{t}_config"
    tileinfo << ti
  end

  bba.l("wire_data_#{$dev_name}", "WireInfoPOD")
  wireinfo.each_with_index do |info, wire|
    bba.s(info["name"].gsub('/', ':'), "name")
    bba.u8(info["name_x"], "name_x")
    bba.u8(info["name_y"], "name_y")
    bba.u16(0, "padding")
    bba.r_slice(info["list_uphill"],   info["num_uphill"],   "pips_uphill")
    bba.r_slice(info["list_downhill"], info["num_downhill"], "pips_downhill")
    bba.r_slice(info["list_bel_pins"], info["num_bel_pins"], "bel_pins")

    num_segments = 0
    $wire_segments[wire].each_value { |segs| num_segments += segs.length }

    if num_segments > 0
      bba.r_slice("wire_segments_#{wire}", num_segments, "segments")
    else
      bba.u32(0, "segments")
      bba.u32(0, "segments_len")
    end

    bba.u32(wiredelay(wire, $fast_timings), "fast_delay")
    bba.u32(wiredelay(wire, $slow_timings), "slow_delay")

    bba.u8(info["x"], "x")
    bba.u8(info["y"], "y")
    bba.u8(0, "z")  # FIXME
    bba.u8($wiretypes[wire_type(info["name"])], "type")
  end

  $num_wires.times do |wire|
    if $wire_segments[wire].length > 0
      bba.l("wire_segments_#{wire}", "WireSegmentPOD")
      $wire_segments[wire].sort.each do |xy, segs|
        segs.each do |seg|
          bba.u8(xy[0], "x")
          bba.u8(xy[1], "y")
          bba.u16($gfx_wire_ids["TILE_WIRE_" + seg.upcase.gsub("/", "_")], "index")
        end
      end
    end
  end

  bba.l("pip_data_#{$dev_name}", "PipInfoPOD")
  pipinfo.each do |info|
    src_seg     = -1
    src_segname = $wire_names_r[info["src"]]
    if $wire_segments[info["src"]].key?([info["x"], info["y"]])
      src_segname = $wire_segments[info["src"]][[info["x"], info["y"]]][0]
      src_seg     = $gfx_wire_ids["TILE_WIRE_" + src_segname.upcase.gsub("/", "_")]
      src_segname = src_segname.gsub("/", ".")
    end

    dst_seg     = -1
    dst_segname = $wire_names_r[info["dst"]]
    if $wire_segments[info["dst"]].key?([info["x"], info["y"]])
      dst_segname = $wire_segments[info["dst"]][[info["x"], info["y"]]][0]
      dst_seg     = $gfx_wire_ids["TILE_WIRE_" + dst_segname.upcase.gsub("/", "_")]
      dst_segname = dst_segname.gsub("/", ".")
    end

    bba.u32(info["src"],          "src")
    bba.u32(info["dst"],          "dst")
    bba.u32(info["fast_delay"],   "fast_delay")
    bba.u32(info["slow_delay"],   "slow_delay")
    bba.u8(info["x"],             "x")
    bba.u8(info["y"],             "y")
    bba.u16(src_seg,              "src_seg")
    bba.u16(dst_seg,              "dst_seg")
    bba.u16(info["switch_mask"],  "switch_mask")
    bba.u32(info["switch_index"], "switch_index")
    bba.u32(info["flags"],        "flags")
  end

  switchinfo = []
  $switches.each do |switch|
    x, y, bits, bel = switch
    bitlist = []
    bits.each do |b|
      m = $cbit_re.match(b)
      raise "cbit_re match failed for #{b}" unless m
      bitlist << [m[1].to_i, m[2].to_i]
    end
    si = {}
    si["x"]    = x
    si["y"]    = y
    si["bits"] = bitlist
    si["bel"]  = bel
    switchinfo << si
  end

  bba.l("switch_data_#{$dev_name}", "SwitchInfoPOD")
  switchinfo.each do |info|
    bba.u32(info["bits"].length, "num_bits")
    bba.u32(info["bel"],        "bel")
    bba.u8(info["x"],           "x")
    bba.u8(info["y"],           "y")
    5.times do |i|
      if i < info["bits"].length
        bba.u8(info["bits"][i][0], "row<#{i}>")
        bba.u8(info["bits"][i][1], "col<#{i}>")
      else
        bba.u8(0, "row<#{i}> (unused)")
        bba.u8(0, "col<#{i}> (unused)")
      end
    end
  end

  bba.l("tile_data_#{$dev_name}", "TileInfoPOD")
  tileinfo.each do |info|
    bba.u8(info["cols"],  "cols")
    bba.u8(info["rows"],  "rows")
    bba.u16(0,            "padding")
    bba.r_slice(info["entries"], info["num_entries"], "entries")
  end

  bba.l("ieren_data_#{$dev_name}", "IerenInfoPOD")
  $ierens.each do |ieren|
    bba.u8(ieren[0], "iox")
    bba.u8(ieren[1], "ioy")
    bba.u8(ieren[2], "ioz")
    bba.u8(ieren[3], "ierx")
    bba.u8(ieren[4], "iery")
    bba.u8(ieren[5], "ierz")
  end

  bba.u16(0, "padding") if $ierens.length % 2 == 1

  bba.l("bits_info_#{$dev_name}", "BitstreamInfoPOD")
  bba.r_slice("tile_data_#{$dev_name}",   tileinfo.length,   "tiles_nonrouting")
  bba.r_slice("switch_data_#{$dev_name}", switchinfo.length, "switches")
  bba.r_slice("ieren_data_#{$dev_name}",  $ierens.length,    "ierens")

  bba.l("tile_grid_#{$dev_name}", "TileType")
  tilegrid.each { |t| bba.u32($tiletypes[t], "tiletype") }

  $extra_cell_config.sort.each do |bel_idx, entries|
    if entries.length > 0
      bba.l("bel#{bel_idx}_config_entries", "BelConfigEntryPOD")
      entries.each do |entry|
        bba.s(entry[0],    "entry_name")
        bba.s(entry[1][2], "cbit_name")
        bba.u8(entry[1][0], "x")
        bba.u8(entry[1][1], "y")
        bba.u16(0,          "padding")
      end
    end
  end

  if $extra_cell_config.length > 0
    bba.l("bel_config_#{$dev_name}", "BelConfigPOD")
    $extra_cell_config.sort.each do |bel_idx, entries|
      bba.u32(bel_idx, "bel_index")
      bba.r_slice(entries.length > 0 ? "bel#{bel_idx}_config_entries" : nil, entries.length, "entries")
    end
  end

  bba.l("package_info_#{$dev_name}", "PackageInfoPOD")
  packageinfo.each do |info|
    bba.s(info[0], "name")
    bba.r_slice(info[2], info[1], "pins")
  end

  cell_timings.sort.each do |cell, timings|
    beltype = $constids[cell]
    bba.l("cell_paths_#{beltype}", "CellPathDelayPOD")
    timings.each do |entry|
      fromport, toport, fast, slow = entry
      bba.u32($constids[fromport], "from_port")
      bba.u32($constids[toport],   "to_port")
      bba.u32(fast,                "fast_delay")
      bba.u32(slow,                "slow_delay")
    end
  end

  bba.l("cell_timings_#{$dev_name}", "CellTimingPOD")
  cell_timings.sort.each do |cell, timings|
    beltype = $constids[cell]
    bba.u32(beltype, "type")
    bba.r_slice("cell_paths_#{beltype}", timings.length, "path_delays")
  end

  bba.l("global_network_info_#{$dev_name}", "GlobalNetworkInfoPOD")
  $glbinfo.length.times do |i|
    ['gb_x', 'gb_y', 'pi_gb_x', 'pi_gb_y', 'pi_gb_pio', 'pi_eb_bank'].each do |k|
      bba.u8($glbinfo[i][k], k)
    end
    ['pi_eb_x', 'pi_eb_y'].each do |k|
      bba.u16($glbinfo[i][k], k)
    end
    bba.u16(0, "padding")
  end

  bba.l("chip_info_#{$dev_name}")
  bba.u32($dev_width,  "dev_width")
  bba.u32($dev_height, "dev_height")
  bba.u32(switchinfo.length, "num_switches")
  bba.r_slice("bel_data_#{$dev_name}",  $bel_name.length, "bel_data")
  bba.r_slice("wire_data_#{$dev_name}", $num_wires,       "wire_data")
  bba.r_slice("pip_data_#{$dev_name}",  pipinfo.length,   "pip_data")
  bba.r_slice("tile_grid_#{$dev_name}", tilegrid.length,  "tile_grid")
  bba.r("bits_info_#{$dev_name}", "bits_info")
  bba.r_slice($extra_cell_config.length > 0 ? "bel_config_#{$dev_name}" : nil, $extra_cell_config.length, "bel_config")
  bba.r_slice("package_info_#{$dev_name}", packageinfo.length,    "packages_data")
  bba.r_slice("cell_timings_#{$dev_name}", cell_timings.length,   "cell_timing")
  bba.r_slice("global_network_info_#{$dev_name}", $glbinfo.length, "global_network_info")
  bba.r_slice("tile_wire_names", $gfx_wire_names.length, "tile_wire_names")

  bba.pop
end

# ---- Helper functions ----

def gfx_wire_alias(old_name, new_name)
  raise "#{old_name} not in gfx_wire_ids" unless $gfx_wire_ids.key?(old_name)
  raise "#{new_name} already in gfx_wire_ids" if $gfx_wire_ids.key?(new_name)
  $gfx_wire_ids[new_name] = $gfx_wire_ids[old_name]
end

def read_timings(filename)
  db   = {}
  cell = nil
  File.open(filename) do |f|
    f.each_line do |line|
      line = line.split
      next if line.length == 0
      if line[0] == "CELL"
        cell = line[1]
      end
      if line[0] == "IOPATH"
        key = "#{cell}.#{line[1]}.#{line[2]}"
        v1  = line[3].split(":")[2]
        v2  = line[4].split(":")[2]
        v1  = v1 == "*" ? 0 : v1.to_f
        v2  = v2 == "*" ? 0 : v2.to_f
        db[key] = [v1, v2].max
      end
    end
  end
  db
end

def init_tiletypes(device)
  if ["5k", "u4k"].include?(device)
    $num_tile_types = 10
  else
    $num_tile_types = 5
  end
  $tile_sizes = Hash[$num_tile_types.times.map { |i| [i, [0, 0]] }]
  $tile_bits  = Array.new($num_tile_types) { [] }
end

def maj_wire_name(name)
  return true if name[2].start_with?("lutff_")
  return true if name[2].start_with?("io_")
  return true if name[2].start_with?("ram/")
  if name[2].start_with?("sp4_h_r_")
    return ["sp4_h_r_0","sp4_h_r_1","sp4_h_r_2","sp4_h_r_3","sp4_h_r_4","sp4_h_r_5",
            "sp4_h_r_6","sp4_h_r_7","sp4_h_r_8","sp4_h_r_9","sp4_h_r_10","sp4_h_r_11"].include?(name[2])
  end
  if name[2].start_with?("sp4_v_b_")
    return ["sp4_v_b_0","sp4_v_b_1","sp4_v_b_2","sp4_v_b_3","sp4_v_b_4","sp4_v_b_5",
            "sp4_v_b_6","sp4_v_b_7","sp4_v_b_8","sp4_v_b_9","sp4_v_b_10","sp4_v_b_11"].include?(name[2])
  end
  if name[2].start_with?("sp12_h_r_")
    return ["sp12_h_r_0","sp12_h_r_1"].include?(name[2])
  end
  if name[2].start_with?("sp12_v_b_")
    return ["sp12_v_b_0","sp12_v_b_1"].include?(name[2])
  end
  false
end

def norm_wire_xy(x, y, name)
  return nil if name.start_with?("glb_netwk_")
  return nil if name.start_with?("neigh_op_")
  return nil if name.start_with?("logic_op_")
  return nil if name.start_with?("io_global/latch")
  nil # FIXME
  # [x, y]
end

def cmp_wire_names(newname, oldname)
  return true  if maj_wire_name(newname)
  return false if maj_wire_name(oldname)

  if newname[2].start_with?("sp") && oldname[2].start_with?("sp")
    m1 = newname[2].match(/.*_(\d+)$/)
    m2 = oldname[2].match(/.*_(\d+)$/)
    if m1 && m2
      idx1 = m1[1].to_i
      idx2 = m2[1].to_i
      return idx1 < idx2 if idx1 != idx2
    end
  end

  newname < oldname
end

def wire_type(name)
  parts = name.split('/')

  if parts[0].start_with?("X") && parts[1]&.start_with?("Y")
    parts = parts[2..]
  end

  return "SP4_V"  if parts[0].start_with?("sp4_v_") || parts[0].start_with?("sp4_r_v_") || parts[0].start_with?("span4_vert_")
  return "SP4_H"  if parts[0].start_with?("sp4_h_") || parts[0].start_with?("span4_horz_")
  return "SP12_V" if parts[0].start_with?("sp12_v_") || parts[0].start_with?("span12_vert_")
  return "SP12_H" if parts[0].start_with?("sp12_h_") || parts[0].start_with?("span12_horz_")
  return "GLB2LOCAL" if parts[0].start_with?("glb2local")
  return "GLB_NETWK" if parts[0].start_with?("glb_netwk_")
  return "LOCAL"     if parts[0].start_with?("local_")

  if parts[0].start_with?("lutff_")
    if parts[1]&.start_with?("in_")
      return parts[1].end_with?("_lut") ? "LUTFF_IN_LUT" : "LUTFF_IN"
    end
    return "LUTFF_LOUT" if parts[1] == "lout"
    return "LUTFF_OUT"  if parts[1] == "out"
    return "LUTFF_COUT" if parts[1] == "cout"
  end

  if parts[0] == "ram"
    return "LUTFF_IN"     if parts[1]&.start_with?("RADDR_")
    return "LUTFF_IN"     if parts[1]&.start_with?("WADDR_")
    return "LUTFF_IN"     if parts[1]&.start_with?("WDATA_")
    return "LUTFF_IN"     if parts[1]&.start_with?("MASK_")
    return "LUTFF_OUT"    if parts[1]&.start_with?("RDATA_")
    return "LUTFF_GLOBAL" if ["WCLK","WCLKE","WE","RCLK","RCLKE","RE"].include?(parts[1])
  end

  if parts[0].start_with?("io_")
    return "LUTFF_IN"  if parts[1]&.start_with?("D_IN_") || parts[1] == "OUT_ENB"
    return "LUTFF_OUT" if parts[1]&.start_with?("D_OUT_")
  end

  return "LUTFF_IN"     if parts[0] == "fabout"
  return "LUTFF_GLOBAL" if parts[0] == "lutff_global" || parts[0] == "io_global"
  return "CARRY_IN_MUX" if parts[0] == "carry_in_mux"
  return "LUTFF_COUT"   if parts[0] == "carry_in"
  return "NONE"         if parts[0].start_with?("neigh_op_")
  return "NONE"         if parts[0].start_with?("padin_")

  "NONE"
end

def pipdelay(src_idx, dst_idx, db)
  return 0 if db.nil?

  src      = $wire_names_r[src_idx]
  dst      = $wire_names_r[dst_idx]
  src_type = wire_type(src[2])
  dst_type = wire_type(dst[2])

  if dst[2].start_with?("sp4_") || dst[2].start_with?("span4_")
    if src[2].start_with?("sp12_") || src[2].start_with?("span12_")
      return db["Sp12to4.I.O"]
    end
    return db["IoSpan4Mux.I.O"] if src[2].start_with?("span4_")
    return dst[2].start_with?("sp4_h_") ? db["Span4Mux_h4.I.O"] : db["Span4Mux_v4.I.O"]
  end

  if dst[2].start_with?("sp12_") || dst[2].start_with?("span12_")
    return dst[2].start_with?("sp12_h_") ? db["Span12Mux_h12.I.O"] : db["Span12Mux_v12.I.O"]
  end

  return 0 if ["fabout", "clk"].include?(dst[2])  # FIXME?
  return 0 if src[2].start_with?("glb_netwk_") && dst[2].start_with?("glb2local_")  # FIXME?

  return db["ICE_CARRY_IN_MUX.carryinitin.carryinitout"] if dst[2] == "carry_in_mux"

  if ["lutff_global/clk","io_global/inclk","io_global/outclk","ram/RCLK","ram/WCLK"].include?(dst[2])
    return db["ClkMux.I.O"]
  end

  if ["lutff_global/s_r","io_global/latch","ram/RE","ram/WE"].include?(dst[2])
    return db["SRMux.I.O"]
  end

  if ["lutff_global/cen","io_global/cen","ram/RCLKE","ram/WCLKE"].include?(dst[2])
    return db["CEMux.I.O"]
  end

  return db["LocalMux.I.O"] if dst[2].start_with?("local_")

  io_out_wires = ["io_0/D_OUT_0","io_0/D_OUT_1","io_0/OUT_ENB","io_1/D_OUT_0","io_1/D_OUT_1","io_1/OUT_ENB"]
  if src[2].start_with?("local_") && io_out_wires.include?(dst[2])
    return db["IoInMux.I.O"]
  end

  return db["InMux.I.O"] if dst[2].match(/^lutff_\d+\/in_\d+$/)
  return 0                if dst[2].match(/^lutff_\d+\/in_\d+_lut/)
  return db["InMux.I.O"] if dst[2].match(/^ram\/(MASK|RADDR|WADDR|WDATA)_/)

  if dst[2].match(/^lutff_\d+\/out/)
    return db["LogicCell40.in0.lcout"] if src[2].match(/^lutff_\d+\/in_0/)
    return db["LogicCell40.in1.lcout"] if src[2].match(/^lutff_\d+\/in_1/)
    return db["LogicCell40.in2.lcout"] if src[2].match(/^lutff_\d+\/in_2/)
    return db["LogicCell40.in3.lcout"] if src[2].match(/^lutff_\d+\/in_3/)
  end

  $stderr.puts "#{src} #{dst} #{src_idx} #{dst_idx} #{src_type} #{dst_type}"
  raise "pipdelay: unhandled case"
end

def wiredelay(wire_idx, db)
  return 0 if db.nil?
  # FIXME
  0
end

def add_wire(x, y, name)
  wire_idx      = $num_wires
  $num_wires   += 1
  wname         = [x, y, name]
  $wire_names[wname]    = wire_idx
  $wire_names_r[wire_idx] = wname
  $wire_segments[wire_idx] = {}
  tile_wire_key = "TILE_WIRE_" + wname[2].upcase.gsub("/", "_")
  if $gfx_wire_ids.key?(tile_wire_key)
    xy_key = [wname[0], wname[1]]
    $wire_segments[wire_idx][xy_key] ||= []
    $wire_segments[wire_idx][xy_key] << wname[2]
  end
  wire_idx
end

def add_switch(x, y, bel = -1)
  $switches << [x, y, [], bel]
end

def add_pip(src, dst, flags = 0)
  x, y, _, _ = $switches[-1]

  $wire_downhill[src] ||= Set.new
  $wire_downhill[src].add(dst)

  $wire_uphill[dst] ||= Set.new
  $wire_uphill[dst].add(src)

  $pip_xy[[src, dst]] = [x, y, 0, $switches.length - 1, flags]
end

def add_bel_input(bel, wire, port)
  $wire_belports[wire] ||= Set.new
  $wire_belports[wire].add([bel, port])
  $bel_wires[bel] << [$constids[port], 0, wire]
end

def add_bel_output(bel, wire, port)
  $wire_belports[wire] ||= Set.new
  $wire_belports[wire].add([bel, port])
  $bel_wires[bel] << [$constids[port], 1, wire]
end

def add_bel_lc(x, y, z)
  bel = $bel_name.length
  $bel_name  << [x, y, "lc#{z}"]
  $bel_type  << "ICESTORM_LC"
  $bel_pos   << [x, y, z]
  $bel_wires << []

  wire_cen = $wire_names[[x, y, "lutff_global/cen"]]
  wire_clk = $wire_names[[x, y, "lutff_global/clk"]]
  wire_s_r = $wire_names[[x, y, "lutff_global/s_r"]]

  wire_cin = if z == 0
    $wire_names[[x, y, "carry_in_mux"]]
  else
    $wire_names[[x, y, "lutff_#{z-1}/cout"]]
  end

  wire_in_0 = add_wire(x, y, "lutff_#{z}/in_0_lut")
  wire_in_1 = add_wire(x, y, "lutff_#{z}/in_1_lut")
  wire_in_2 = add_wire(x, y, "lutff_#{z}/in_2_lut")
  wire_in_3 = add_wire(x, y, "lutff_#{z}/in_3_lut")

  wire_out  = $wire_names[[x, y, "lutff_#{z}/out"]]
  wire_cout = $wire_names[[x, y, "lutff_#{z}/cout"]]
  wire_lout = z < 7 ? $wire_names[[x, y, "lutff_#{z}/lout"]] : nil

  add_bel_input(bel, wire_cen, "CEN")
  add_bel_input(bel, wire_clk, "CLK")
  add_bel_input(bel, wire_s_r, "SR")
  add_bel_input(bel, wire_cin, "CIN")

  add_bel_input(bel, wire_in_0, "I0")
  add_bel_input(bel, wire_in_1, "I1")
  add_bel_input(bel, wire_in_2, "I2")
  add_bel_input(bel, wire_in_3, "I3")

  add_bel_output(bel, wire_out,  "O")
  add_bel_output(bel, wire_cout, "COUT")
  add_bel_output(bel, wire_lout, "LO") unless wire_lout.nil?

  # route-through LUTs
  add_switch(x, y, bel)
  add_pip(wire_in_0, wire_out, 1)
  add_pip(wire_in_1, wire_out, 1)
  add_pip(wire_in_2, wire_out, 1)
  add_pip(wire_in_3, wire_out, 1)

  # LUT permutation pips
  4.times do |i|
    add_switch(x, y, bel)
    4.times do |j|
      flags = if (i == j) || ([i, j] == [1, 2]) || ([i, j] == [2, 1])
        0
      else
        2
      end
      add_pip($wire_names[[x, y, "lutff_#{z}/in_#{i}"]],
              $wire_names[[x, y, "lutff_#{z}/in_#{j}_lut"]], flags)
    end
  end
end

def add_bel_io(x, y, z)
  bel = $bel_name.length
  $bel_name  << [x, y, "io#{z}"]
  $bel_type  << "SB_IO"
  $bel_pos   << [x, y, z]
  $bel_wires << []

  wire_cen   = $wire_names[[x, y, "io_global/cen"]]
  wire_iclk  = $wire_names[[x, y, "io_global/inclk"]]
  wire_latch = $wire_names[[x, y, "io_global/latch"]]
  wire_oclk  = $wire_names[[x, y, "io_global/outclk"]]

  wire_din_0  = $wire_names[[x, y, "io_#{z}/D_IN_0"]]
  wire_din_1  = $wire_names[[x, y, "io_#{z}/D_IN_1"]]
  wire_dout_0 = $wire_names[[x, y, "io_#{z}/D_OUT_0"]]
  wire_dout_1 = $wire_names[[x, y, "io_#{z}/D_OUT_1"]]
  wire_out_en = $wire_names[[x, y, "io_#{z}/OUT_ENB"]]

  add_bel_input(bel, wire_cen,   "CLOCK_ENABLE")
  add_bel_input(bel, wire_iclk,  "INPUT_CLK")
  add_bel_input(bel, wire_oclk,  "OUTPUT_CLK")
  add_bel_input(bel, wire_latch, "LATCH_INPUT_VALUE")

  add_bel_output(bel, wire_din_0, "D_IN_0")
  add_bel_output(bel, wire_din_1, "D_IN_1")

  add_bel_input(bel, wire_dout_0, "D_OUT_0")
  add_bel_input(bel, wire_dout_1, "D_OUT_1")
  add_bel_input(bel, wire_out_en, "OUTPUT_ENABLE")

  $glbinfo.each do |gidx, ginfo|
    if [ginfo['pi_gb_x'], ginfo['pi_gb_y'], ginfo['pi_gb_pio']] == [x, y, z]
      add_bel_output(bel, $wire_names[[x, y, "glb_netwk_#{gidx}"]], "GLOBAL_BUFFER_OUTPUT")
    end
  end
end

def add_bel_ram(x, y)
  bel = $bel_name.length
  $bel_name  << [x, y, "ram"]
  $bel_type  << "ICESTORM_RAM"
  $bel_pos   << [x, y, 0]
  $bel_wires << []

  if $wire_names.key?([x, y, "ram/WE"])
    # iCE40 1K-style memories
    y0, y1 = y, y + 1
  else
    # iCE40 8K-style memories
    y1, y0 = y, y + 1
  end

  16.times do |i|
    add_bel_input( bel, $wire_names[[x, i < 8 ? y0 : y1, "ram/MASK_#{i}"]],  "MASK_#{i}")
    add_bel_input( bel, $wire_names[[x, i < 8 ? y0 : y1, "ram/WDATA_#{i}"]], "WDATA_#{i}")
    add_bel_output(bel, $wire_names[[x, i < 8 ? y0 : y1, "ram/RDATA_#{i}"]], "RDATA_#{i}")
  end

  11.times do |i|
    add_bel_input(bel, $wire_names[[x, y0, "ram/WADDR_#{i}"]], "WADDR_#{i}")
    add_bel_input(bel, $wire_names[[x, y1, "ram/RADDR_#{i}"]], "RADDR_#{i}")
  end

  add_bel_input(bel, $wire_names[[x, y0, "ram/WCLK"]],  "WCLK")
  add_bel_input(bel, $wire_names[[x, y0, "ram/WCLKE"]], "WCLKE")
  add_bel_input(bel, $wire_names[[x, y0, "ram/WE"]],    "WE")

  add_bel_input(bel, $wire_names[[x, y1, "ram/RCLK"]],  "RCLK")
  add_bel_input(bel, $wire_names[[x, y1, "ram/RCLKE"]], "RCLKE")
  add_bel_input(bel, $wire_names[[x, y1, "ram/RE"]],    "RE")
end

def add_bel_gb(xy, x, y, g)
  return if xy[0] != x || xy[1] != y

  bel = $bel_name.length
  $bel_name  << [x, y, "gb"]
  $bel_type  << "SB_GB"
  $bel_pos   << [x, y, 2]
  $bel_wires << []

  add_bel_input( bel, $wire_names[[x, y, "fabout"]],         "USER_SIGNAL_TO_GLOBAL_BUFFER")
  add_bel_output(bel, $wire_names[[x, y, "glb_netwk_#{g}"]], "GLOBAL_BUFFER_OUTPUT")
end

def is_ec_wire(ec_entry)
  $wire_names.key?(ec_entry[1])
end

def is_ec_output(ec_entry)
  wirename = ec_entry[1][2]
  return true if wirename.include?("O_") || wirename.include?("slf_op_")
  return true if wirename.include?("neigh_op_")
  return true if wirename.include?("glb_netwk_")
  false
end

def is_ec_pll_clock_output(ec, ec_entry)
  ec[0] == 'PLL' && ['PLLOUT_A', 'PLLOUT_B'].include?(ec_entry[0])
end

def add_pll_clock_output(bel, ec, entry)
  io_x, io_y, io_z = entry[1]
  io_zs = "io_#{io_z}/D_IN_0"
  io_z  = io_z.to_i
  add_bel_output(bel, $wire_names[[io_x, io_y, io_zs]], entry[0])

  $glbinfo.each do |gidx, ginfo|
    if [ginfo['pi_gb_x'], ginfo['pi_gb_y'], ginfo['pi_gb_pio']] == [io_x, io_y, io_z]
      add_bel_output(bel, $wire_names[[io_x, io_y, "glb_netwk_#{gidx}"]], entry[0] + '_GLOBAL')
    end
  end
end

def add_bel_ec(ec)
  ectype, x, y, z = ec
  bel = $bel_name.length
  $extra_cell_config[bel] = []
  $bel_name  << [x, y, "#{ectype.downcase}_#{z}"]
  $bel_type  << ectype
  $bel_pos   << [x, y, z]
  $bel_wires << []

  $extra_cells[ec].each do |entry|
    if is_ec_wire(entry)
      if is_ec_output(entry)
        add_bel_output(bel, $wire_names[entry[1]], entry[0])
      else
        add_bel_input(bel, $wire_names[entry[1]], entry[0])
      end
    elsif is_ec_pll_clock_output(ec, entry)
      add_pll_clock_output(bel, ec, entry)
    else
      $extra_cell_config[bel] << entry
    end
  end

  if ectype == "MAC16"
    if y == 5
      last_dsp_y = 0
    elsif y == 10
      last_dsp_y = 5
    elsif y == 13
      last_dsp_y = 5
    elsif y == 15
      last_dsp_y = 10
    elsif y == 23
      last_dsp_y = 23
    else
      raise "unknown DSP y #{y}"
    end

    add_if_new = lambda do |ax, ay, aname|
      if $wire_names.key?([ax, ay, aname])
        $wire_names[[ax, ay, aname]]
      else
        add_wire(ax, ay, aname)
      end
    end

    wire_signextin  = add_if_new.call(x, last_dsp_y, "dsp/signextout")
    wire_signextout = add_if_new.call(x, y,          "dsp/signextout")
    wire_accumci    = add_if_new.call(x, last_dsp_y, "dsp/accumco")
    wire_accumco    = add_if_new.call(x, y,          "dsp/accumco")

    add_bel_input( bel, wire_signextin,  "SIGNEXTIN")
    add_bel_output(bel, wire_signextout, "SIGNEXTOUT")
    add_bel_input( bel, wire_accumci,    "ACCUMCI")
    add_bel_output(bel, wire_accumco,    "ACCUMCO")
  end
end

# ---- BinaryBlobAssembler class ----

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
    raise "string contains pipe: #{str}" if str.include?("|")
    puts "str |#{str}| #{comment}"
  end

  def u8(v, comment)
    if comment.nil?
      puts "u8 #{v}"
    else
      puts "u8 #{v} #{comment}"
    end
  end

  def u16(v, comment)
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

main if __FILE__ == $PROGRAM_NAME
