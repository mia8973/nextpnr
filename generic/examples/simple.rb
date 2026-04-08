require_relative 'simple_config'

def is_io(x, y)
  x == 0 || x == X - 1 || y == 0 || y == Y - 1
end

X.times do |x|
  Y.times do |y|
    # Bel port wires
    N.times do |z|
      $ctx.addWire(name: "X#{x}Y#{y}Z#{z}_CLK", type: "BEL_CLK", x: x, y: y)
      $ctx.addWire(name: "X#{x}Y#{y}Z#{z}_Q", type: "BEL_Q", x: x, y: y)
      $ctx.addWire(name: "X#{x}Y#{y}Z#{z}_F", type: "BEL_F", x: x, y: y)
      K.times do |i|
        $ctx.addWire(name: "X#{x}Y#{y}Z#{z}_I#{i}", type: "BEL_I", x: x, y: y)
      end
    end
    # Local wires
    Wl.times do |l|
      $ctx.addWire(name: "X#{x}Y#{y}_LOCAL#{l}", type: "LOCAL", x: x, y: y)
    end
    # Create bels
    if is_io(x, y)
      next if x == y
      2.times do |z|
        $ctx.addBel(name: "X#{x}Y#{y}_IO#{z}", type: "GENERIC_IOB", loc: Loc(x, y, z), gb: false, hidden: false)
        $ctx.addBelInput(bel: "X#{x}Y#{y}_IO#{z}", name: "I", wire: "X#{x}Y#{y}Z#{z}_I0")
        $ctx.addBelInput(bel: "X#{x}Y#{y}_IO#{z}", name: "EN", wire: "X#{x}Y#{y}Z#{z}_I1")
        $ctx.addBelOutput(bel: "X#{x}Y#{y}_IO#{z}", name: "O", wire: "X#{x}Y#{y}Z#{z}_Q")
      end
    else
      N.times do |z|
        $ctx.addBel(name: "X#{x}Y#{y}_SLICE#{z}", type: "GENERIC_SLICE", loc: Loc(x, y, z), gb: false, hidden: false)
        $ctx.addBelInput(bel: "X#{x}Y#{y}_SLICE#{z}", name: "CLK", wire: "X#{x}Y#{y}Z#{z}_CLK")
        K.times do |k|
          $ctx.addBelInput(bel: "X#{x}Y#{y}_SLICE#{z}", name: "I[#{k}]", wire: "X#{x}Y#{y}Z#{z}_I#{k}")
        end
        $ctx.addBelOutput(bel: "X#{x}Y#{y}_SLICE#{z}", name: "F", wire: "X#{x}Y#{y}Z#{z}_F")
        $ctx.addBelOutput(bel: "X#{x}Y#{y}_SLICE#{z}", name: "Q", wire: "X#{x}Y#{y}Z#{z}_Q")
      end
    end
  end
end

X.times do |x|
  Y.times do |y|
    # Pips driving bel input wires
    # Bel input wires are driven by every Si'th local with an offset
    create_input_pips = lambda do |dst, offset, skip|
      (offset % skip).step(Wl - 1, skip) do |i|
        src = "X#{x}Y#{y}_LOCAL#{i}"
        $ctx.addPip(name: "X#{x}Y#{y}.#{src}.#{dst}", type: "BEL_INPUT",
          srcWire: src, dstWire: dst, delay: $ctx.getDelayFromNS(0.05), loc: Loc(x, y, 0))
      end
    end
    N.times do |z|
      create_input_pips.call("X#{x}Y#{y}Z#{z}_CLK", 0, Si)
      K.times do |k|
        create_input_pips.call("X#{x}Y#{y}Z#{z}_I#{k}", k % Si, Si)
      end
    end

    # Pips from bel outputs to locals
    create_output_pips = lambda do |dst, offset, skip|
      (offset % skip).step(N - 1, skip) do |i|
        src = "X#{x}Y#{y}Z#{i}_F"
        $ctx.addPip(name: "X#{x}Y#{y}.#{src}.#{dst}", type: "BEL_OUTPUT",
          srcWire: src, dstWire: dst, delay: $ctx.getDelayFromNS(0.05), loc: Loc(x, y, 0))
        src = "X#{x}Y#{y}Z#{i}_Q"
        $ctx.addPip(name: "X#{x}Y#{y}.#{src}.#{dst}", type: "BEL_OUTPUT",
          srcWire: src, dstWire: dst, delay: $ctx.getDelayFromNS(0.05), loc: Loc(x, y, 0))
      end
    end
    # Pips from neighbour locals to locals
    create_neighbour_pips = lambda do |dst, nx, ny, offset, skip|
      return if nx < 0 || nx >= X || ny < 0 || ny >= Y
      (offset % skip).step(Wl - 1, skip) do |i|
        src = "X#{nx}Y#{ny}_LOCAL#{i}"
        $ctx.addPip(name: "X#{x}Y#{y}.#{src}.#{dst}", type: "NEIGHBOUR",
          srcWire: src, dstWire: dst, delay: $ctx.getDelayFromNS(0.05), loc: Loc(x, y, 0))
      end
    end
    Wl.times do |l|
      dst = "X#{x}Y#{y}_LOCAL#{l}"
      create_output_pips.call(dst, l % Sq, Sq)
      create_neighbour_pips.call(dst, x - 1, y - 1, (l + 1) % Sl, Sl)
      create_neighbour_pips.call(dst, x - 1, y,     (l + 2) % Sl, Sl)
      create_neighbour_pips.call(dst, x - 1, y + 1, (l + 2) % Sl, Sl)
      create_neighbour_pips.call(dst, x,     y - 1, (l + 3) % Sl, Sl)
      create_neighbour_pips.call(dst, x,     y + 1, (l + 4) % Sl, Sl)
      create_neighbour_pips.call(dst, x + 1, y - 1, (l + 5) % Sl, Sl)
      create_neighbour_pips.call(dst, x + 1, y,     (l + 6) % Sl, Sl)
      create_neighbour_pips.call(dst, x + 1, y + 1, (l + 7) % Sl, Sl)
    end
  end
end
