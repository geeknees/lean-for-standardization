# ABOUTME: Exercise the actual comparison driver against prefix-only differences and invalid traces.
# ABOUTME: Verify that a wrong expected result fails the run and leaves an incomplete report.
require_relative 'run'
require 'tempfile'

MozillaComparison.prepare!
input = { 'events' => [
  { 'kind' => 'https', 'answer' => 'service', 'hints' => [{ 'family' => 'ipv6', 'address' => 6 }] },
  { 'kind' => 'dnsAAAA', 'addresses' => [6] }
] }
result = MozillaComparison.compare(input)
raise 'Test must converge to equal final observations' unless result['lean']['final'] == result['mozilla']['final']
raise 'Lost the earlier difference after convergence' unless result['differences'] == [{ 'event' => 0, 'fields' => ['starts'] }]
puts 'PASS a prefix difference survives equal final observations'

begin
  MozillaComparison.compare('events' => [{ 'kind' => 'failure', 'family' => 'ipv6', 'address' => 6 }])
  raise 'Invalid callback was counted as a difference'
rescue MozillaComparison::InvalidTrace
  puts 'PASS callbacks without attempts are rejected as invalid input'
end

fixture = JSON.parse(File.read(File.join(__dir__, 'fixtures/failure-spacing.json')))
minimal = MozillaComparison.minimize_spacing(fixture.slice('config', 'events'))
raise 'Unexpected witness size' unless minimal['input']['events'].length == 3
raise 'Witness still has a removable event' if minimal['deletion_checks'].any? { |check| check['witness'] }
raise 'Invalid deletion candidates were not recorded' unless minimal['deletion_checks'].any? { |check| !check['valid_input'] }
puts 'PASS a three-event spacing witness is minimal under valid single-event deletions'

fixture['expect']['differences'] = []
Tempfile.create(['mozilla-wrong-expectation', '.json']) do |file|
  file.write(JSON.generate(fixture))
  file.flush
  _output, error, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, 'run.rb'), file.path)
  raise 'Wrong expectation did not fail for the intended reason' unless status.exitstatus == 1 && error.include?('Unexpected prefix differences')
  report = JSON.parse(File.read(MozillaComparison::REPORT))
  raise 'Failed run left a complete report' unless report['complete'] == false && report['error']
end
puts 'PASS unexpected differences fail the command and mark the report incomplete'
