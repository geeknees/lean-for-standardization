# ABOUTME: Compare each common trace prefix against Lean and the unchanged Mozilla implementation.
# ABOUTME: Pin expected differences explicitly and retain provenance in an ignored local report.
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'time'

module MozillaComparison
  class InvalidTrace < StandardError; end
  ROOT = File.expand_path('../../..', __dir__)
  MANIFEST = File.join(ROOT, 'specs/happy-eyeballs/manifest.json')
  CARGO_MANIFEST = File.join(__dir__, 'Cargo.toml')
  ORACLE = File.join(ROOT, '.lake/build/bin/oracle')
  ADAPTER = File.join(ROOT, '.tools/mozilla-target/debug/mozilla-he-adapter')
  REPORT = File.join(ROOT, '.tools/mozilla-comparison/report.json')
  CARGO_ENV = { 'CARGO_HOME' => File.join(ROOT, '.tools/cargo-home'),
                'CARGO_TARGET_DIR' => File.join(ROOT, '.tools/mozilla-target') }.freeze
  FIELDS = %w[starts winner cancelled].freeze
  OPTIONAL_CONFIG = { 'svcbReliant' => false, 'mayBecomeReliant' => false,
                      'dnsProtected' => false, 'supportsSecurityParam' => false,
                      'reliesOnSecurityParam' => false }.freeze

  module_function

  def capture(*command, env: {}, stdin: '')
    output, error, status = Open3.capture3(env, *command, stdin_data: stdin, chdir: ROOT)
    raise "#{File.basename(command.first)} exited #{status.exitstatus}: #{error}" unless status.success?
    output
  end

  # These files use Cargo's generated lockfile v4 subset: package identity and string dependencies.
  def lock_packages(path)
    File.read(path).split(/^\[\[package\]\]\s*$/).drop(1).map do |block|
      package = %w[name version source checksum].to_h { |key| [key, block[/^#{key} = "([^"]+)"$/, 1]] }
      package['dependencies'] = (block[/^dependencies = \[(.*?)^\]/m, 1] || '').scan(/^ "([^"]+)"/).flatten
      package
    end
  end

  def verify_dependency_closure!
    upstream = lock_packages(File.join(ROOT, 'specs/happy-eyeballs/mozilla/Cargo.lock'))
    packages = lock_packages(File.join(__dir__, 'Cargo.lock'))
    pending = [packages.find { |p| p['name'] == 'happy-eyeballs' } || raise('Mozilla dependency missing')]
    visited = []
    until pending.empty?
      package = pending.shift
      next if visited.include?(package)
      visited << package
      if package['source']
        identity = package.slice('name', 'version', 'source', 'checksum')
        raise "Dependency drift from upstream lock: #{package['name']} #{package['version']}" unless
          upstream.any? { |p| p.slice('name', 'version', 'source', 'checksum') == identity }
      end
      package['dependencies'].each do |dependency|
        name, version = dependency.split(' ', 3)
        candidates = packages.select { |p| p['name'] == name && (!version || p['version'] == version) }
        raise "Ambiguous or missing lock dependency: #{dependency}" unless candidates.length == 1
        pending << candidates.first
      end
    end
    visited.map { |p| p.slice('name', 'version', 'checksum') }
  end

  def prepare!
    capture(RbConfig.ruby, 'scripts/check.rb')
    dependencies = verify_dependency_closure!
    elan = File.join(ROOT, '.tools/elan')
    lake = File.join(elan, 'bin/lake')
    if File.executable?(lake)
      capture(lake, 'build', 'oracle', env: { 'ELAN_HOME' => elan })
    else
      capture('lake', 'build', 'oracle')
    end
    capture('cargo', 'build', '--locked', '--offline', '--manifest-path', CARGO_MANIFEST, env: CARGO_ENV)
    dependencies
  end

  def projection(state)
    { 'starts' => state.fetch('starts'), 'winner' => state.fetch('winner'),
      'cancelled' => state.fetch('cancelled').sort_by { |ep| [ep.fetch('family'), ep.fetch('address')] } }
  end

  def lean_trace(input)
    config = OPTIONAL_CONFIG.merge(input.fetch('config', {}))
    events = []
    timeline = input.fetch('events').map do |event|
      if event.fetch('kind') == 'success'
        # A public Mozilla success callback denotes a fully established connection.
        # Supply that completion to Lean's separate TCP/TLS stages; TLS timing is not observed.
        %w[transportReady beginTls success].each { |kind| events << event.merge('kind' => kind) }
      else
        events << event
      end
      # The environment polls both implementations after every input and explicit time advance.
      # Lean has a separate start proposal; it retains all of its own admission checks.
      events << { 'kind' => 'start' }
      result = JSON.parse(capture(ORACLE, 'happy-eyeballs', '-', stdin: JSON.generate('config' => config, 'events' => events)))
      raise 'Lean safety check failed' unless result.fetch('valid')
      projection(result)
    end
    { 'timeline' => timeline, 'final' => timeline.last || { 'starts' => [], 'winner' => nil, 'cancelled' => [] } }
  end

  def compare(input)
    # Validate the common domain through the Rust adapter first. Invalid callbacks,
    # unsupported security settings, and infrastructure errors are not protocol differences.
    output, error, status = Open3.capture3(ADAPTER, stdin_data: JSON.generate(input), chdir: ROOT)
    unless status.success?
      if status.exitstatus == 1 && error.match?(/\Aevent \d+: (callback has no emitted attempt|DNS response has no pending query)/)
        raise InvalidTrace, error.strip
      end
      raise "Mozilla adapter failed (#{status.exitstatus}): #{error}"
    end
    mozilla = JSON.parse(output)
    lean = lean_trace(input)
    raise 'Adapter returned a different prefix count' unless mozilla.fetch('timeline').length == lean.fetch('timeline').length
    differences = lean.fetch('timeline').zip(mozilla.fetch('timeline')).each_with_index.filter_map do |(left, right), index|
      fields = FIELDS.select { |field| left.fetch(field) != right.fetch(field) }
      { 'event' => index, 'fields' => fields } unless fields.empty?
    end
    { 'lean' => lean, 'mozilla' => mozilla, 'differences' => differences }
  end

  def spacing_witness?(result)
    times = ->(implementation) { result.fetch(implementation).fetch('final').fetch('starts').map { |s| s.fetch('at') } }
    times.call('mozilla').each_cons(2).any? { |a, b| b - a < 10 } &&
      times.call('lean').each_cons(2).all? { |a, b| b - a >= 10 }
  end

  def deletion_probe(input, index)
    events = input.fetch('events').each_with_index.reject { |_, i| i == index }.map(&:first)
    candidate = input.merge('events' => events)
    result = compare(candidate)
    { 'removed_event' => index, 'input' => candidate, 'valid_input' => true,
      'witness' => spacing_witness?(result), 'lean' => result['lean']['final'], 'mozilla' => result['mozilla']['final'] }
  rescue InvalidTrace => error
    { 'removed_event' => index, 'input' => candidate, 'valid_input' => false, 'witness' => false, 'reason' => error.message }
  end

  def minimize_spacing(input)
    raise 'Trace does not witness the spacing difference' unless spacing_witness?(compare(input))
    attempts = []
    loop do
      reduction = input.fetch('events').each_index.find do |index|
        probe = deletion_probe(input, index)
        attempts << probe
        if probe['witness']
          input = probe.fetch('input')
          true
        end
      end
      break unless reduction
    end
    checks = input.fetch('events').each_index.map { |index| deletion_probe(input, index) }
    raise 'Spacing witness was not deletion-minimal' if checks.any? { |check| check['witness'] }
    result = compare(input)
    { 'input' => input, 'lean' => result['lean']['final'], 'mozilla' => result['mozilla']['final'],
      'event_deletion_minimal' => true, 'deletion_checks' => checks, 'reduction_attempts' => attempts }
  end

  def check_expectation!(fixture, result)
    expect = fixture.fetch('expect')
    raise 'Unexpected prefix differences' unless result.fetch('differences') == expect.fetch('differences')
    %w[lean mozilla].each do |implementation|
      raise "Unexpected #{implementation} final observation" unless
        result.fetch(implementation).fetch('final') == expect.fetch(implementation)
    end
  end

  def dns_permutations
    inputs = [{ 'kind' => 'dnsA', 'addresses' => [4] },
              { 'kind' => 'dnsAAAA', 'addresses' => [6] },
              { 'kind' => 'https', 'answer' => 'noData' }]
    final = { 'starts' => [{ 'endpoint' => { 'family' => 'ipv6', 'address' => 6 }, 'at' => 0 },
                          { 'endpoint' => { 'family' => 'ipv4', 'address' => 4 }, 'at' => 250 }],
              'winner' => nil, 'cancelled' => [] }
    inputs.permutation.map.with_index do |events, index|
      ["dns-permutation-#{index + 1}", { 'events' => events + [{ 'kind' => 'advance', 'ms' => 250 }],
                                       'expect' => { 'differences' => [], 'lean' => final, 'mozilla' => final } }]
    end
  end

  def provenance(dependencies)
    paths = %w[lean-toolchain lakefile.toml lake-manifest.json] + Dir.glob('*.lean', base: ROOT) +
            Dir.glob('LeanForStandardization/**/*.lean', base: ROOT) +
            Dir.glob('tests/happy-eyeballs/mozilla/{*.rb,Cargo.*,src/*.rs,fixtures/*.json}', base: ROOT)
    { 'implementation' => JSON.parse(File.read(MANIFEST)).fetch('implementation'),
      'rustc' => capture('rustc', '--version').strip, 'cargo' => capture('cargo', '--version').strip,
      'source_manifest_sha256' => Digest::SHA256.file(MANIFEST).hexdigest,
      'upstream_dependency_closure' => dependencies,
      'source_hashes' => paths.sort.to_h { |path| [path, Digest::SHA256.file(File.join(ROOT, path)).hexdigest] },
      'binary_hashes' => { 'lean_oracle' => Digest::SHA256.file(ORACLE).hexdigest,
                          'mozilla_adapter' => Digest::SHA256.file(ADAPTER).hexdigest } }
  end

  def run(paths = [])
    report = { 'complete' => false, 'started_at' => Time.now.utc.iso8601, 'cases' => [] }
    FileUtils.mkdir_p(File.dirname(REPORT))
    File.write(REPORT, JSON.pretty_generate(report) + "\n")
    begin
      report['provenance'] = provenance(prepare!)
      fixtures = (paths.empty? ? Dir[File.join(__dir__, 'fixtures/*.json')].sort : paths).map do |path|
        [File.basename(path, '.json'), JSON.parse(File.read(path))]
      end
      fixtures += dns_permutations if paths.empty?
      raise 'No comparison fixtures found' if fixtures.empty?
      fixtures.each do |name, fixture|
        input = fixture.slice('config', 'events')
        result = compare(input)
        report['cases'] << { 'name' => name, 'input' => input }.merge(result)
        check_expectation!(fixture, result)
        puts "#{result['differences'].empty? ? 'MATCH' : 'EXPECTED DIFFERENCE'} #{name}"
      end
      if (witness = report['cases'].find { |entry| entry['name'] == 'failure-spacing' })
        report['spacing_witness'] = minimize_spacing(witness.fetch('input'))
        FileUtils.mkdir_p(File.dirname(REPORT))
        File.write(File.join(File.dirname(REPORT), 'failure-spacing-minimized.json'),
                   JSON.pretty_generate(report['spacing_witness'].fetch('input')) + "\n")
        puts "Spacing witness: #{report['spacing_witness']['input']['events'].length} events, single-deletion checks complete."
      end
      report['complete'] = true
      report['matches'] = report['cases'].count { |c| c['differences'].empty? }
      puts "Checked #{fixtures.length} traces: #{report['matches']} match, #{fixtures.length - report['matches']} recorded differences."
    rescue StandardError => error
      report['error'] = error.message
      warn error.message
      return false
    ensure
      FileUtils.mkdir_p(File.dirname(REPORT))
      File.write(REPORT, JSON.pretty_generate(report) + "\n")
    end
    true
  end
end

exit(MozillaComparison.run(ARGV) ? 0 : 1) if $PROGRAM_NAME == __FILE__
