def visit(indent, data)
  istr = " " * indent
  puts "#{istr}#{data.name}: #{data.type}"
  data.leaf_cells.each do |lname, gname|
    puts "#{istr}    #{lname} -> #{gname}"
  end
  data.hier_cells.each do |lname, gname|
    visit(indent + 4, $ctx.hierarchy[gname])
  end
end

visit(0, $ctx.hierarchy[$ctx.top_module])
