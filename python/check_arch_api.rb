# Script to do Arch API sanity checking.
#
# This script can be used to do some sanity checking of either wire to
# wire connectivity or bel pin wire connectivity.
#
# Wire to wire connectivity is tested by supplying a source and destination wire
# and verifying that a pip exists that connects those wires.
#
# Bel pin wire connectivity is tested by supplying a bel and pin name and the
# connected wire.
#
# Invoke in a working directory that contains a file name "test_data.yaml":
#   ${NEXTPNR} --run ${NEXTPNR_SRC}/check_arch_api.rb
#
# "test_data.yaml" should contain the test vectors for the wire to wire or bel
# pin connectivity tests. Example test_data.yaml:
#
# pip_test:
#     - src_wire: CLBLM_R_X11Y93/CLBLM_L_D3
#       dst_wire: SLICE_X15Y93.SLICEL/D3
# pip_chain_test:
#     - wires:
#         - $CONSTANTS_X0Y0.$CONSTANTS/$GND_SOURCE
#         - $CONSTANTS_X0Y0/$GND_NODE
#         - TIEOFF_X3Y145.TIEOFF/$GND_SITE_WIRE
# bel_pin_test:
#     - bel: SLICE_X15Y93.SLICEL/D6LUT
#       pin: A3
#       wire: SLICE_X15Y93.SLICEL/D3

# Simple YAML parser for the subset of YAML used by test_data.yaml
# (mruby does not have a built-in YAML library, so we parse manually)
def parse_simple_yaml(filename)
  result = {}
  current_key = nil
  current_list = nil
  current_item = nil
  current_wires = nil

  File.readlines(filename).each do |line|
    stripped = line.rstrip
    next if stripped.empty? || stripped.start_with?("#")

    indent = line.length - line.lstrip.length

    if indent == 0 && stripped.end_with?(":")
      current_key = stripped.chomp(":")
      result[current_key] = []
      current_list = result[current_key]
      current_item = nil
      current_wires = nil
    elsif stripped.start_with?("- ") && current_list
      if stripped.include?(": ")
        current_item = {}
        current_list << current_item
        pair = stripped[2..]
        k, v = pair.split(": ", 2)
        current_item[k.strip] = v.strip
        current_wires = nil
      elsif stripped.strip == "- wires:"
        current_item = { "wires" => [] }
        current_list << current_item
        current_wires = current_item["wires"]
      else
        if current_wires
          current_wires << stripped.strip.sub(/\A- /, "")
        end
      end
    elsif current_item && stripped.include?(": ")
      pair = stripped.strip
      if pair.start_with?("- ")
        if current_wires
          current_wires << pair[2..].strip
        else
          k, v = pair[2..].split(": ", 2)
          current_item[k.strip] = v.strip
        end
      else
        k, v = pair.split(": ", 2)
        if k.strip == "wires"
          current_wires = []
          current_item["wires"] = current_wires
        else
          current_item[k.strip] = v.strip
          current_wires = nil
        end
      end
    elsif current_wires && stripped.strip.start_with?("- ")
      current_wires << stripped.strip[2..].strip
    end
  end

  result
end

def check_arch_api(ctx)
  success = true
  pips_tested = 0
  pips_failed = 0

  test_pip = lambda do |src_wire_name, dst_wire_name|
    pip = nil
    ctx.getPipsDownhill(src_wire_name).each do |pip_name|
      if ctx.getPipDstWire(pip_name) == dst_wire_name
        pip = pip_name
        src_wire = ctx.getPipSrcWire(pip_name)
        raise "Assertion failed: #{src_wire} != #{src_wire_name}" unless src_wire == src_wire_name
      end
    end

    if pip.nil?
      success = false
      pips_failed += 1
      puts "Pip from #{src_wire_name} to #{dst_wire_name} failed"
    else
      pips_tested += 1
    end
  end

  bel_pins_tested = 0

  test_data = parse_simple_yaml("test_data.yaml")

  if test_data.key?("pip_test")
    test_data["pip_test"].each do |pip_test|
      test_pip.call(pip_test["src_wire"], pip_test["dst_wire"])
    end
  end

  if test_data.key?("pip_chain_test")
    test_data["pip_chain_test"].each do |chain_test|
      wires = chain_test["wires"]
      wires.each_cons(2) do |src_wire, dst_wire|
        test_pip.call(src_wire, dst_wire)
      end
    end
  end

  if test_data.key?("bel_pin_test")
    test_data["bel_pin_test"].each do |bel_pin_test|
      wire_name = ctx.getBelPinWire(bel_pin_test["bel"], bel_pin_test["pin"])
      raise "Assertion failed: #{bel_pin_test['wire']} != #{wire_name}" unless bel_pin_test["wire"] == wire_name

      if bel_pin_test.key?("type")
        pin_type = ctx.getBelPinType(bel_pin_test["bel"], bel_pin_test["pin"])
        raise "Assertion failed: #{bel_pin_test['type']} != #{pin_type}" unless bel_pin_test["type"] == pin_type.name
      end

      bel_pins_tested += 1
    end
  end

  puts "Tested #{pips_tested} pips and #{bel_pins_tested} bel pins"

  if !success
    puts "#{pips_failed} pips failed"
    exit(-1)
  end
end

check_arch_api($ctx)
