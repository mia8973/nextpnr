#!/usr/bin/env ruby

require 'fileutils'

num_runs = 8

unless File.exist?("picorv32.json")
  system("wget", "https://raw.githubusercontent.com/cliffordwolf/picorv32/master/picorv32.v", exception: true)
  system("yosys", "-q", "-p", "synth_ice40 -json picorv32.json -top top", "picorv32.v", "picorv32_top.v", exception: true)
end

fmax = {}

FileUtils.mkdir_p("picorv32_work") unless File.exist?("picorv32_work")

threads = []

(1..num_runs).each do |run|
  threads << Thread.new do
    ascfile = "picorv32_work/picorv32_s#{run}.asc"
    File.delete(ascfile) if File.exist?(ascfile)
    result = system("../nextpnr-ice40", "--hx8k", "--seed", run.to_s, "--json", "picorv32.json",
                    "--asc", ascfile, "--freq", "40", "--opt-timing",
                    [:out, :err] => File::NULL)
    if !result
      puts "Run #{run} failed!"
    else
      icetime_res = `icetime -d hx8k #{ascfile}`
      fmax_m = icetime_res.match(/\(([0-9.]+) MHz\)/)
      fmax[run] = fmax_m[1].to_f
    end
  end
end

threads.each(&:join)

fmax_min = fmax.values.min
fmax_max = fmax.values.max
fmax_avg = fmax.values.sum.to_f / fmax.size

puts "#{fmax.size}/#{num_runs} runs passed"
puts "icetime: min = #{fmax_min} MHz, avg = #{fmax_avg} MHz, max = #{fmax_max} MHz"
