# Run ./nextpnr-ice40 --json ice40/blinky.json --run python/dump_design.rb
$ctx.cells.sort_by { |x| x.first }.each do |cell, cinfo|
  puts "Cell #{cell} : #{cinfo.type}"
  puts "\tPorts:"
  cinfo.ports.sort_by { |x| x.first }.each do |port, pinfo|
    dir = [" <-- ", " --> ", " <-> "][pinfo.type.to_i]
    unless pinfo.net.nil?
      puts "\t\t#{port} #{dir} #{pinfo.net.name}"
    end
  end

  if cinfo.attrs.length > 0
    puts "\tAttrs:"
    cinfo.attrs.each do |attr, val|
      puts "\t\t#{attr}: #{val}"
    end
  end

  if cinfo.params.length > 0
    puts "\tParams:"
    cinfo.params.each do |param, val|
      if val =~ /\A\d+\z/
        bin_val = val.to_i.to_s(2)
        val = "#{bin_val.length}'b#{bin_val}"
      end
      puts "\t\t#{param}: #{val}"
    end
  end

  unless cinfo.bel.nil?
    puts "\tBel: #{cinfo.bel}"
  end
  puts
end
