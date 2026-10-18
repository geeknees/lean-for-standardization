# ABOUTME: Verify pinned source hashes, fixture syntax, and supplementary proof hygiene.
# ABOUTME: Leave proof trust checks to Audit.lean's transitive dependency inspection.
require 'digest'
require 'json'

Dir.chdir(File.expand_path('..', __dir__))
errors = []
manifests = Dir['specs/*/manifest.json'].sort
errors << 'Expected a source manifest for each track.' unless manifests.length == 2
manifests.each do |path|
  manifest = JSON.parse(File.read(path))
  manifest.fetch('files').each do |entry|
    file = File.join(File.dirname(path), entry.fetch('path'))
    unless File.file?(file)
      errors << "Missing source snapshot: #{file}"
      next
    end
    bytes = File.binread(file)
    errors << "SHA256 mismatch: #{file}" unless Digest::SHA256.hexdigest(bytes) == entry.fetch('sha256')
    if entry['git_blob_sha1']
      blob = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0" + bytes)
      errors << "Git blob mismatch: #{file}" unless blob == entry['git_blob_sha1']
    end
  end
end

sources = Dir['LeanForStandardization/**/*.lean'] + Dir['*.lean']
sources.each do |path|
  text = File.read(path)
  errors << "Missing ABOUTME preamble: #{path}" unless text.lines.take(2).all? { |line| line.start_with?('-- ABOUTME:') }
  # This deliberately simple lint also checks comments. It is not the proof audit.
  text.each_line.with_index(1) do |line, index|
    next if line.lstrip.start_with?('--')
    if line.match?(/\b(?:sorry|admit|native_decide)\b/) || line.match?(/^\s*(?:(?:private|protected)\s+)?axiom\s/)
      errors << "Disallowed proof escape in #{path}:#{index}"
    end
  end
end
Dir['tests/{happy-eyeballs,erc8004}/*.json'].each do |file|
  JSON.parse(File.read(file))
end
(['README.md', 'AGENTS.md'] + Dir['docs/*.md']).each do |file|
  File.read(file).scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |target|
    next if target.match?(/\A(?:https?:|mailto:|#)/)
    relative = target.split('#').first
    resolved = File.expand_path(relative, File.dirname(file))
    errors << "Broken local link in #{file}: #{target}" unless File.exist?(resolved)
  end
end
abort errors.join("\n") unless errors.empty?
puts "Source snapshots, document links, and supplementary source checks passed (#{sources.length} Lean files)."
