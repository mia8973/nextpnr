class BBAWriter
  def initialize(f)
    @f = f
  end

  def pre(s)
    @f.puts "pre #{s}"
  end

  def post(s)
    @f.puts "post #{s}"
  end

  def push(s)
    @f.puts "push #{s}"
  end

  def ref(r, comment = "")
    @f.puts "ref #{r} #{comment}"
  end

  def slice(r, size, comment = "")
    @f.puts "ref #{r} #{comment}"
    @f.puts "u32 #{size}"
  end

  def str(s, comment = "")
    @f.puts "str |#{s}| #{comment}"
  end

  def label(s)
    @f.puts "label #{s}"
  end

  def u8(n, comment = "")
    raise "expected Integer, got #{n.inspect}" unless n.is_a?(Integer)
    @f.puts "u8 #{n} #{comment}"
  end

  def u16(n, comment = "")
    raise "expected Integer, got #{n.inspect}" unless n.is_a?(Integer)
    @f.puts "u16 #{n} #{comment}"
  end

  def u32(n, comment = "")
    raise "expected Integer, got #{n.inspect}" unless n.is_a?(Integer)
    @f.puts "u32 #{n} #{comment}"
  end

  def pop
    @f.puts "pop"
  end
end
