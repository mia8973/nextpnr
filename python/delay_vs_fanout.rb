File.open("delay_vs_fanout.csv", "w") do |f|
  f.puts "fanout,delay"
  $ctx.nets.each do |net_name, net|
    next if net.driver.cell.nil?
    next if net.driver.cell.type == "DCCA" # ignore global clocks
    net.users.each do |user|
      f.puts "#{net.users.length},#{$ctx.getNetinfoRouteDelay(net, user)}"
    end
  end
end
