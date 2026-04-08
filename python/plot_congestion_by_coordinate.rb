# Plot congestion by coordinate - outputs CSV data
# (matplotlib is not available in mruby, so raw data is output instead of plots)
#
# Usage: provide the data directory as ARGV[0]

data = []

file_idx = 1
loop do
  filename = "#{ARGV[0]}/heatmap_congestion_by_coordinate_#{file_idx}.csv"
  puts filename
  break unless File.exist?(filename)

  file_data = []
  File.open(filename) do |f|
    f.each_line do |line|
      row = line.chomp.split(",").reject { |x| x == "" }.map { |x| x.to_f }
      file_data << row
    end
  end
  data << file_data
  file_idx += 1
end

data.each_with_index do |file_data, i|
  out_filename = "#{ARGV[0]}/heatmap_congestion_by_coordinate_#{format('%03d', i)}.csv"
  File.open(out_filename, "w") do |f|
    f.puts "# heatmap for iteration #{i + 1}"
    file_data.each do |row|
      f.puts row.join(",")
    end
  end
  puts "Wrote #{out_filename}"
end
