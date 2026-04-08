$ctx.createRectangularRegion("osc", 1, 1, 1, 4)
$ctx.cells.each do |cell, cellinfo|
  if cellinfo.attrs.key?("ringosc")
    puts "Floorplanned cell #{cell}"
    $ctx.constrainCellToRegion(cell, "osc")
  end
end
