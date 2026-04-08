require_relative 'write_fasm'
require_relative 'simple_config'

# Need to tell FASM generator how to write parameters
# [celltype, parameter] -> ParameterConfig
param_map = {
  ["GENERIC_SLICE", "K"] => ParameterConfig.new(write: false),
  ["GENERIC_SLICE", "INIT"] => ParameterConfig.new(write: true, numeric: true, width: 2**K),
  ["GENERIC_SLICE", "FF_USED"] => ParameterConfig.new(write: true, numeric: true, width: 1),

  ["GENERIC_IOB", "INPUT_USED"] => ParameterConfig.new(write: true, numeric: true, width: 1),
  ["GENERIC_IOB", "OUTPUT_USED"] => ParameterConfig.new(write: true, numeric: true, width: 1),
  ["GENERIC_IOB", "ENABLE_USED"] => ParameterConfig.new(write: true, numeric: true, width: 1),
}

File.open("blinky.fasm", "w") do |f|
  write_fasm($ctx, param_map, f)
end
