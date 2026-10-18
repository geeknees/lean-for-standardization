# ABOUTME: Execute saved JSON traces against the Lean executable and check expected observations.
# ABOUTME: Compare recursively specified expectations while preserving exact array order and size.
require 'json'
require 'open3'

def matches?(expected, actual)
  case expected
  when Hash
    actual.is_a?(Hash) && expected.all? { |key, value| actual.key?(key) && matches?(value, actual[key]) }
  when Array
    actual.is_a?(Array) && expected.length == actual.length && expected.zip(actual).all? { |a, b| matches?(a, b) }
  else
    expected == actual
  end
end

root = File.expand_path('..', __dir__)
Dir.chdir(root)
oracle = File.join(root, '.lake/build/bin/oracle')
abort 'Run lake build first: oracle executable is missing.' unless File.executable?(oracle)
files = Dir['tests/{happy-eyeballs,erc8004}/*.json'].sort
abort 'No JSON scenarios found.' if files.empty?
files.each do |file|
  fixture = JSON.parse(File.read(file))
  abort "Missing nonempty expect object: #{file}" unless fixture['expect'].is_a?(Hash) && !fixture['expect'].empty?
  track = file.split('/')[1]
  output, error, status = Open3.capture3(oracle, track, file)
  abort "Oracle failed: #{file}\n#{error}" unless status.success?
  actual = JSON.parse(output)
  abort "Unexpected result: #{file}\nExpected subset: #{fixture['expect'].inspect}\nActual: #{actual.inspect}" unless matches?(fixture['expect'], actual)
  puts "PASS #{file}"
end

%w[happy-eyeballs erc8004].each do |track|
  ['{', '{}'].each do |bad_input|
    _output, _error, status = Open3.capture3(oracle, track, '-', stdin_data: bad_input)
    abort "Malformed input unexpectedly accepted: #{track} #{bad_input.inspect}" if status.success?
  end
end
puts "Checked #{files.length} saved scenarios and malformed JSON/schema rejection."
