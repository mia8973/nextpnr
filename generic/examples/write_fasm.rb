ParameterConfig = Struct.new(:write, :numeric, :width, :alias_name) do
  def initialize(write: false, numeric: true, width: 1, alias_name: nil)
    super(write, numeric, width, alias_name)
  end
end

#
# Write a design as FASM
#
#   ctx:       nextpnr context
#   paramCfg:  map from [celltype, parametername] -> ParameterConfig describing how to write parameters
#   f:         output file
#
def write_fasm(ctx, paramCfg, f)
  ctx.nets.sort_by { |x| x[1].name.to_s }.each do |nname, net|
    f.puts "# Net #{nname}"
    net.wires.sort_by { |x| x[1].to_s }.each do |wire, pip|
      unless pip.pip.nil?
        f.puts pip.pip.to_s
      end
    end
    f.puts ""
  end
  ctx.cells.sort_by { |x| x[1].name.to_s }.each do |cname, cell|
    f.puts "# Cell #{cname} at #{cell.bel}"
    cell.params.sort_by { |x| x.to_s }.each do |param, val|
      cfg = paramCfg[[cell.type, param]]
      next unless cfg.write
      fasm_name = cfg.alias_name.nil? ? param : cfg.alias_name
      if cfg.numeric
        if cfg.width == 1
          if val.to_i != 0
            f.puts "#{cell.bel}.#{fasm_name}"
          end
        else
          # Parameters with width >32 are direct binary, otherwise denary
          f.puts "#{cell.bel}.#{fasm_name}[#{cfg.width - 1}:0] = #{cfg.width}'b#{val}"
        end
      else
        f.puts "#{cell.bel}.#{fasm_name}.#{val}"
      end
    end
    f.puts ""
  end
end
