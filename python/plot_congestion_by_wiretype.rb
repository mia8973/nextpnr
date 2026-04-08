# Plot congestion by wiretype - outputs consolidated CSV data
# (matplotlib is not available in mruby, so raw data is output instead of plots)
#
# Usage: provide the data directory as ARGV[0]

data = {}
max_bars = {}

file_idx = 1
loop do
  filename = "#{ARGV[0]}/heatmap_congestion_by_wiretype_#{file_idx}.csv"
  puts filename
  break unless File.exist?(filename)

  File.open(filename) do |f|
    lines = f.readlines
    lines[1..].each do |line|
      row = line.chomp.split(",")
      key = row[0]
      values = row[1..].reject { |x| x == "" }.map { |x| x.to_f }
      # Ignore wires without overuse
      values[0] = 0
      values[1] = 0
      unless data.key?(key)
        data[key] = []
        max_bars[key] = 0
      end
      data[key] << values
      max_bars[key] = [max_bars[key], values.length].max
    end
  end
  file_idx += 1
end
file_idx -= 1

to_remove = []
data.each_key do |key|
  if data[key].map { |values| values.sum }.sum == 0
    # Prune entries that never have any overuse to attempt to reduce visual clutter
    to_remove << key
  else
    # Pad entries as needed
    data[key].each do |values|
      while values.length < max_bars[key]
        values << 0
      end
    end
  end
end
to_remove.each { |key| data.delete(key) }

# Output consolidated CSV for each iteration
file_idx.times do |i|
  out_filename = "#{ARGV[0]}/heatmap_congestion_by_wiretype_#{format('%03d', i)}.csv"
  File.open(out_filename, "w") do |f|
    f.puts "# heatmap for iteration #{i}"
    f.puts "wiretype,#{(0...max_bars.values.max).to_a.join(',')}"
    data.each do |key, iterations|
      if iterations[i].sum > 0
        f.puts "#{key},#{iterations[i].join(',')}"
      end
    end
  end
  puts "Wrote #{out_filename}"
end
