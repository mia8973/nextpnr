# Pass this file to one of the script arguments (e.g. --pre-place interactive.rb)
# to drop to a command-line interactive session in the middle of place and route

puts "Press Ctrl+D to finish interactive session"
loop do
  print ">> "
  line = gets
  break if line.nil?
  begin
    result = eval(line.chomp)
    puts "=> #{result.inspect}" unless result.nil?
  rescue => e
    puts "Error: #{e.message}"
  end
end
