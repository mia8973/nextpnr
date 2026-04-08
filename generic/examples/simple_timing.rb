$ctx.cells.each do |cname, cell|
  next if cell.type != "GENERIC_SLICE"
  next if ["$PACKER_GND", "$PACKER_VCC"].include?(cname)
  k = cell.params["K"].to_i
  $ctx.addCellTimingClock(cell: cname, port: "CLK")
  k.times do |i|
    $ctx.addCellTimingSetupHold(cell: cname, port: "I[#{i}]", clock: "CLK",
      setup: $ctx.getDelayFromNS(0.2), hold: $ctx.getDelayFromNS(0))
  end
  $ctx.addCellTimingClockToOut(cell: cname, port: "Q", clock: "CLK", clktoq: $ctx.getDelayFromNS(0.2))
  k.times do |i|
    $ctx.addCellTimingDelay(cell: cname, fromPort: "I[#{i}]", toPort: "F", delay: $ctx.getDelayFromNS(0.2))
  end
end
