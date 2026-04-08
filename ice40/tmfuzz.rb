#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# ../nextpnr-ice40 --hx8k --tmfuzz > tmfuzz_hx8k.txt
# ../nextpnr-ice40 --lp8k --tmfuzz > tmfuzz_lp8k.txt
# ../nextpnr-ice40 --up5k --tmfuzz > tmfuzz_up5k.txt

# NOTE: This script requires the 'numo-narray' and 'matplotlib' (or equivalent)
# gems for full functionality. The numpy/matplotlib portions are translated
# to use numo-narray where possible, but Ruby lacks a direct matplotlib equivalent.
# Consider using 'gruff', 'gnuplot', or exporting data for external plotting.

begin
  require 'numo/narray'
rescue LoadError
  abort "This script requires the 'numo-narray' gem. Install with: gem install numo-narray"
end

device = "hx8k"
# device = "lp8k"
# device = "up5k"

sel_src_type = "LUTFF_OUT"
sel_dst_type = "LUTFF_IN_LUT"

#-- Read fuzz data

src_dst_pairs = Hash.new(0)

delay_data = []
all_delay_data = []

delay_map_sum = Numo::DFloat.zeros(41, 41)
delay_map_sum2 = Numo::DFloat.zeros(41, 41)
delay_map_count = Numo::DFloat.zeros(41, 41)

same_tile_delays = []
neighbour_tile_delays = []

type_delta_data = {}

File.open("tmfuzz_%s.txt" % device, "r") do |f|
  dst_xy = nil
  dst_type = nil
  dst_wire = nil

  f.each_line do |line|
    line = line.split

    if line[0] == "dst"
      dst_xy = [line[1].to_i, line[2].to_i]
      dst_type = line[3]
      dst_wire = line[4]
    end

    src_xy = [line[1].to_i, line[2].to_i]
    src_type = line[3]
    src_wire = line[4]

    delay = line[5].to_i
    estdelay = line[6].to_i

    all_delay_data << [delay, estdelay]

    src_dst_pairs[[src_type, dst_type]] += 1

    dx = dst_xy[0] - src_xy[0]
    dy = dst_xy[1] - src_xy[1]

    if src_type == sel_src_type && dst_type == sel_dst_type
      if dx == 0 && dy == 0
        same_tile_delays << delay
      elsif dx.abs <= 1 && dy.abs <= 1
        neighbour_tile_delays << delay
      else
        delay_data << [delay, estdelay, dx, dy, 0, 0, 0]

        relx = 20 + dst_xy[0] - src_xy[0]
        rely = 20 + dst_xy[1] - src_xy[1]

        if (0..40).include?(relx) && (0..40).include?(rely)
          delay_map_sum[relx, rely] += delay
          delay_map_sum2[relx, rely] += delay * delay
          delay_map_count[relx, rely] += 1
        end
      end
    end

    if dst_type == sel_dst_type
      type_delta_data[src_type] ||= []
      type_delta_data[src_type] << [dx, dy, delay]
    end
  end
end

delay_data_arr = Numo::DFloat.cast(delay_data)
all_delay_data_arr = Numo::DFloat.cast(all_delay_data)
max_delay = delay_data_arr[true, 0..1].max

mean_same_tile_delays = neighbour_tile_delays.sum.to_f / neighbour_tile_delays.size
mean_neighbour_tile_delays = neighbour_tile_delays.sum.to_f / neighbour_tile_delays.size

std_same = Math.sqrt(same_tile_delays.map { |v| (v - mean_same_tile_delays) ** 2 }.sum / same_tile_delays.size)
std_neigh = Math.sqrt(neighbour_tile_delays.map { |v| (v - mean_neighbour_tile_delays) ** 2 }.sum / neighbour_tile_delays.size)

printf("Avg same tile delay: %.2f (%.2f std, N=%d)\n",
       mean_same_tile_delays, std_same, same_tile_delays.size)
printf("Avg neighbour tile delay: %.2f (%.2f std, N=%d)\n",
       mean_neighbour_tile_delays, std_neigh, neighbour_tile_delays.size)

#-- Apply simple low-weight bluring to fill gaps (loop runs 0 times)

0.times do
  neigh_sum = Numo::DFloat.zeros(41, 41)
  neigh_sum2 = Numo::DFloat.zeros(41, 41)
  neigh_count = Numo::DFloat.zeros(41, 41)

  41.times do |x|
    41.times do |y|
      (-1..1).each do |p|
        (-1..1).each do |q|
          next if p == 0 && q == 0
          if (0..40).include?(x + p) && (0..40).include?(y + q)
            neigh_sum[x, y] += delay_map_sum[x + p, y + q]
            neigh_sum2[x, y] += delay_map_sum2[x + p, y + q]
            neigh_count[x, y] += delay_map_count[x + p, y + q]
          end
        end
      end
    end
  end

  delay_map_sum  = delay_map_sum  + 0.1 * neigh_sum
  delay_map_sum2 = delay_map_sum2 + 0.1 * neigh_sum2
  delay_map_count = delay_map_count + 0.1 * neigh_count
end

delay_map = delay_map_sum / delay_map_count
delay_map_std = Numo::NMath.sqrt(delay_map_count * delay_map_sum2 - delay_map_sum ** 2) / delay_map_count

#-- Print src-dst-pair summary

puts "Src-Dst-Type pair summary:"
src_dst_pairs.map { |k, v| [v, k[0], k[1]] }.sort.each do |cnt, src, dst|
  marker = (src == sel_src_type && dst == sel_dst_type) ? " *" : ""
  printf("%20s %20s %5d%s\n", src, dst, cnt, marker)
end
puts

#-- Plot estimate vs actual delay (skipped - no matplotlib equivalent in Ruby)
puts "(Plotting skipped - matplotlib not available in Ruby)"
puts

#-- Generate Model #0

def nonlinear_preprocessor0(dx, dy)
  dx, dy = dx.abs, dy.abs
  Numo::DFloat[1.0, dx + dy]
end

a = Numo::DFloat.zeros(41 * 41, nonlinear_preprocessor0(0, 0).size)
b = Numo::DFloat.zeros(41 * 41)

index = 0
41.times do |x|
  41.times do |y|
    if delay_map_count[x, y] > 0
      a[index, true] = nonlinear_preprocessor0(x - 20, y - 20)
      b[index] = delay_map[x, y]
    end
    index += 1
  end
end

# Least squares solve: model0_params = (A^T A)^-1 A^T b
ata = a.transpose.dot(a)
atb = a.transpose.dot(b)
# Simple pseudoinverse for small matrices
model0_params = Numo::Linalg.lstsq(a, b)[0] rescue begin
  # Fallback: manual normal equations
  inv_ata = Numo::Linalg.inv(ata)
  inv_ata.dot(atb)
rescue
  puts "Warning: Could not solve least squares for Model #0"
  Numo::DFloat.zeros(nonlinear_preprocessor0(0, 0).size)
end

puts "Model #0 parameters: #{model0_params.to_a}"

model0_map = Numo::DFloat.zeros(41, 41)
41.times do |x|
  41.times do |y|
    v = model0_params.dot(nonlinear_preprocessor0(x - 20, y - 20))
    model0_map[x, y] = v
  end
end

puts "(Plotting skipped - matplotlib not available in Ruby)"

delay_data.each_with_index do |row, i|
  dx = row[2]
  dy = row[3]
  delay_data[i][4] = model0_params.dot(nonlinear_preprocessor0(dx, dy))
end

nan_mask = delay_map.ne(0) # approximate for nanmean
diff0 = delay_map - model0_map
in_sample_rms = Math.sqrt((diff0 ** 2).mean)
out_delays = delay_data.map { |r| (r[0] - r[4]) ** 2 }
out_sample_rms = Math.sqrt(out_delays.sum / out_delays.size)
printf("In-sample RMS error: %f\n", in_sample_rms)
printf("Out-of-sample RMS error: %f\n", out_sample_rms)
puts

#-- Generate Model #1

def nonlinear_preprocessor1(dx, dy)
  dx, dy = dx.abs.to_f, dy.abs.to_f
  Numo::DFloat[1.0, dx + dy, (dx**2 + dy**2)**(0.5), (dx**3 + dy**3)**(1.0/3.0)]
end

a = Numo::DFloat.zeros(41 * 41, nonlinear_preprocessor1(0, 0).size)
b = Numo::DFloat.zeros(41 * 41)

index = 0
41.times do |x|
  41.times do |y|
    if delay_map_count[x, y] > 0
      a[index, true] = nonlinear_preprocessor1(x - 20, y - 20)
      b[index] = delay_map[x, y]
    end
    index += 1
  end
end

model1_params = Numo::Linalg.lstsq(a, b)[0] rescue begin
  ata = a.transpose.dot(a)
  atb = a.transpose.dot(b)
  Numo::Linalg.inv(ata).dot(atb)
rescue
  puts "Warning: Could not solve least squares for Model #1"
  Numo::DFloat.zeros(nonlinear_preprocessor1(0, 0).size)
end

puts "Model #1 parameters: #{model1_params.to_a}"

model1_map = Numo::DFloat.zeros(41, 41)
41.times do |x|
  41.times do |y|
    v = model1_params.dot(nonlinear_preprocessor1(x - 20, y - 20))
    model1_map[x, y] = v
  end
end

puts "(Plotting skipped - matplotlib not available in Ruby)"

delay_data.each_with_index do |row, i|
  dx = row[2]
  dy = row[3]
  delay_data[i][5] = model1_params.dot(nonlinear_preprocessor1(dx, dy))
end

diff1 = delay_map - model1_map
printf("In-sample RMS error: %f\n", Math.sqrt((diff1 ** 2).mean))
out_delays1 = delay_data.map { |r| (r[0] - r[5]) ** 2 }
printf("Out-of-sample RMS error: %f\n", Math.sqrt(out_delays1.sum / out_delays1.size))
puts

#-- Generate Model #2

def nonlinear_preprocessor2(v)
  Numo::DFloat[1, v, Math.sqrt(v.abs)]
end

a = Numo::DFloat.zeros(41 * 41, nonlinear_preprocessor2(0).size)
b = Numo::DFloat.zeros(41 * 41)

index = 0
41.times do |x|
  41.times do |y|
    if delay_map_count[x, y] > 0
      a[index, true] = nonlinear_preprocessor2(model1_map[x, y])
      b[index] = delay_map[x, y]
    end
    index += 1
  end
end

model2_params = Numo::Linalg.lstsq(a, b)[0] rescue begin
  ata = a.transpose.dot(a)
  atb = a.transpose.dot(b)
  Numo::Linalg.inv(ata).dot(atb)
rescue
  puts "Warning: Could not solve least squares for Model #2"
  Numo::DFloat.zeros(nonlinear_preprocessor2(0).size)
end

puts "Model #2 parameters: #{model2_params.to_a}"

model2_map = Numo::DFloat.zeros(41, 41)
41.times do |x|
  41.times do |y|
    v = model1_params.dot(nonlinear_preprocessor1(x - 20, y - 20))
    v = model2_params.dot(nonlinear_preprocessor2(v))
    model2_map[x, y] = v
  end
end

puts "(Plotting skipped - matplotlib not available in Ruby)"

delay_data.each_with_index do |row, i|
  delay_data[i][6] = model2_params.dot(nonlinear_preprocessor2(delay_data[i][5]))
end

diff2 = delay_map - model2_map
printf("In-sample RMS error: %f\n", Math.sqrt((diff2 ** 2).mean))
out_delays2 = delay_data.map { |r| (r[0] - r[6]) ** 2 }
printf("Out-of-sample RMS error: %f\n", Math.sqrt(out_delays2.sum / out_delays2.size))
puts

#-- Generate deltas for different source net types

type_deltas = {}

puts "Delay deltas for different src types:"
type_delta_data.keys.sort.each do |src_type|
  deltas = []

  type_delta_data[src_type].each do |dx, dy, delay|
    dx = dx.abs
    dy = dy.abs

    if dx > 1 || dy > 1
      est = model0_params[0] + model0_params[1] * (dx + dy)
    else
      est = mean_neighbour_tile_delays
    end
    deltas << (delay - est)
  end

  mean_delta = deltas.sum.to_f / deltas.size
  std_delta = Math.sqrt(deltas.map { |d| (d - mean_delta) ** 2 }.sum / deltas.size)
  printf("%15s: %8.2f (std %6.2f)\n", src_type, mean_delta, std_delta)

  type_deltas[src_type] = mean_delta
end

#-- Print C defs of model parameters

puts "--snip--"
printf("%d, %d, %d,\n",
       mean_neighbour_tile_delays.to_i,
       (128 * model0_params[0]).to_i,
       (128 * model0_params[1]).to_i)
printf("%d, %d, %d, %d,\n",
       (128 * model1_params[0]).to_i,
       (128 * model1_params[1]).to_i,
       (128 * model1_params[2]).to_i,
       (128 * model1_params[3]).to_i)
printf("%d, %d, %d,\n",
       (128 * model2_params[0]).to_i,
       (128 * model2_params[1]).to_i,
       (128 * model2_params[2]).to_i)
printf("%d, %d, %d, %d\n",
       type_deltas["LOCAL"].to_i,
       type_deltas["LUTFF_IN"].to_i,
       ((type_deltas["SP4_H"] + type_deltas["SP4_V"]) / 2).to_i,
       ((type_deltas["SP12_H"] + type_deltas["SP12_V"]) / 2).to_i)
puts "--snap--"
