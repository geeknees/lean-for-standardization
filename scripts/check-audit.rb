# ABOUTME: Confirm that the dependency audit rejects introduced proof escape paths.
# ABOUTME: Generate disposable negative probes without adding unproved facts to project sources.
require 'fileutils'
require 'open3'

Dir.chdir(File.expand_path('..', __dir__))
source = File.read('Audit.lean')
probes = {
  'transitive' => [
    "namespace UntrustedProbe\naxiom fact : False\nend UntrustedProbe\n" \
    "namespace LeanForStandardization\nprivate theorem auditProbe : False := UntrustedProbe.fact\nend LeanForStandardization\n",
    'UntrustedProbe.fact'
  ],
  'admitted' => [
    "namespace LeanForStandardization\ntheorem auditProbe : False := by sorry\nend LeanForStandardization\n",
    'sorryAx'
  ],
  'native' => [
    "namespace LeanForStandardization\ntheorem auditProbe : (1 : Nat) = 1 := by native_decide\nend LeanForStandardization\n",
    'native_decide.ax_'
  ]
}

FileUtils.mkdir_p('.lake/audit-probes')
probes.each do |name, (injection, expected)|
  path = ".lake/audit-probes/#{name}.lean"
  File.write(path, source.sub("\nrun_cmd do", "\n#{injection}\nrun_cmd do"))
  output, error, status = Open3.capture3('lake', 'env', 'lean', path)
  unless !status.success? && (output + error).include?('Unapproved axiom') && (output + error).include?(expected)
    abort "Audit did not reject #{name} for the expected dependency:\n#{output}\n#{error}"
  end
  puts "PASS audit rejects #{name} (#{expected})"
ensure
  FileUtils.rm_f(path) if path
end
