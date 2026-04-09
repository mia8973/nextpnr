# Utilities for SDF file parsing to determine cell timings

class SDFData
  attr_accessor :cells

  def initialize
    @cells = {}
  end
end

class Delay
  attr_accessor :minv, :typv, :maxv

  def initialize(minv, typv, maxv)
    @minv = minv
    @typv = typv
    @maxv = maxv
  end
end

class IOPath
  attr_accessor :from_pin, :to_pin, :rising, :falling

  def initialize(from_pin, to_pin, rising, falling)
    @from_pin = from_pin
    @to_pin = to_pin
    @rising = rising
    @falling = falling
  end
end

class SetupHoldCheck
  attr_accessor :pin, :clock, :setup, :hold

  def initialize(pin, clock, setup, hold)
    @pin = pin
    @clock = clock
    @setup = setup
    @hold = hold
  end
end

class WidthCheck
  attr_accessor :clock, :width

  def initialize(clock, width)
    @clock = clock
    @width = width
  end
end

class Interconnect
  attr_accessor :from_net, :to_net, :rising, :falling

  def initialize(from_net, to_net, rising, falling)
    @from_net = from_net
    @to_net = to_net
    @rising = rising
    @falling = falling
  end
end

class CellData
  attr_accessor :type, :inst, :entries, :interconnect

  def initialize(celltype, inst)
    @type = celltype
    @inst = inst
    @entries = []
    @interconnect = {}
  end
end

def parse_sexpr(stream)
  content = []
  buffer = ""
  instr = false
  loop do
    c = stream.read(1)
    raise "unexpected end of file" if c.nil? || c == ""
    if instr
      if c == '"'
        instr = false
      else
        buffer += c
      end
    else
      if c == '('
        content << parse_sexpr(stream)
      elsif c == ')'
        content << buffer if buffer != ""
        return content
      elsif c =~ /\s/
        if buffer != ""
          content << buffer
        end
        buffer = ""
      elsif c == '"'
        instr = true
      else
        buffer += c
      end
    end
  end
end

def parse_sexpr_file(filename)
  File.open(filename, 'r') do |f|
    c = f.read(1)
    while c != '('
      raise "unexpected char" unless c == ' ' || c == "\n" || c == "\t"
      c = f.read(1)
    end
    return parse_sexpr(f)
  end
end

def parse_delay(delay)
  sp = delay.split(":").map { |x| x == '' ? nil : x.to_f }
  raise "bad delay" unless sp.length == 3
  Delay.new(sp[0], sp[1], sp[2])
end

def parse_sdf_file(filename)
  sdata = parse_sexpr_file(filename)
  raise "not DELAYFILE" unless sdata[0] == "DELAYFILE"
  sdf = SDFData.new
  sdata[1..].each do |entry|
    next if entry[0] != "CELL"
    raise "expected CELLTYPE" unless entry[1][0] == "CELLTYPE"
    celltype = entry[1][1]
    raise "expected INSTANCE" unless entry[2][0] == "INSTANCE"
    if entry[2].length > 1
      inst = entry[2][1]
    else
      inst = "top"
    end
    cell = CellData.new(celltype, inst)
    setups = {}
    holds = {}
    entry[3..].each do |subentry|
      if subentry[0] == "DELAY"
        raise "expected ABSOLUTE" unless subentry[1][0] == "ABSOLUTE"
        subentry[1][1..].each do |delay|
          if delay[0] == "IOPATH"
            cell.entries << IOPath.new(delay[1], delay[2], parse_delay(delay[3][0]), parse_delay(delay[4][0]))
          elsif delay[0] == "INTERCONNECT"
            cell.interconnect[[delay[1], delay[2]]] = Interconnect.new(delay[1], delay[2],
                                                                        parse_delay(delay[3][0]),
                                                                        parse_delay(delay[4][0]))
          end
        end
      elsif subentry[0] == "TIMINGCHECK"
        subentry[1..].each do |check|
          if check[0] == "SETUPHOLD"
            cell.entries << SetupHoldCheck.new(check[1], check[2], parse_delay(check[3][0]), parse_delay(check[4][0]))
          elsif check[0] == "SETUP"
            setups[[check[1], check[2][1]]] = parse_delay(check[3][0])
          elsif check[0] == "HOLD"
            holds[[check[1], check[2][1]]] = parse_delay(check[3][0])
          elsif check[0] == "WIDTH"
            cell.entries << WidthCheck.new(check[1], parse_delay(check[2][0]))
          end
        end
      end
    end
    # merge setups and holds
    setups.each do |k, v|
      next unless holds.key?(k)
      cell.entries << SetupHoldCheck.new(k[0], k[1], v, holds[k])
    end
    sdf.cells[[celltype, inst]] = cell
  end
  sdf
end
