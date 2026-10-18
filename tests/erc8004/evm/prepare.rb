# ABOUTME: Stages pinned upstream Solidity and its required npm lock graph in an ignored tool directory.
# ABOUTME: Verifies source hashes and performs no network access or dependency installation.
require "digest"
require "fileutils"
require "json"

ROOT = File.expand_path("../../..", __dir__)
SOURCES = File.join(ROOT, "specs/erc8004")
PROJECT = File.join(ROOT, ".tools/erc8004-evm")
PACKAGES = %w[hardhat ethers @openzeppelin/contracts @openzeppelin/contracts-upgradeable].freeze

manifest = JSON.parse(File.read(File.join(SOURCES, "manifest.json")))
manifest.fetch("files").each do |entry|
  path = File.join(SOURCES, entry.fetch("path"))
  abort "Source hash mismatch: #{entry.fetch('path')}" unless Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
end

upstream_lock = JSON.parse(File.read(File.join(SOURCES, "upstream/package-lock.json")))
all_packages = upstream_lock.fetch("packages")
dependencies = PACKAGES.to_h { |name| [name, all_packages.fetch("node_modules/#{name}").fetch("version")] }
package = {
  "name" => "erc8004-independent-comparison", "version" => "0.1.0", "private" => true,
  "type" => "module", "devDependencies" => dependencies
}

# Resolve dependency locations from the existing lock, including nested packages.
resolve = lambda do |base, name|
  loop do
    candidate = [base, "node_modules", name].reject(&:empty?).join("/")
    break candidate if all_packages.key?(candidate)
    break nil if base.empty?
    base = base.sub(%r{(?:\A|/)node_modules/(?:@[^/]+/)?[^/]+\z}, "")
  end
end
selected = {}
pending = PACKAGES.map { |name| "node_modules/#{name}" }
until pending.empty?
  path = pending.shift
  next if selected.key?(path)
  entry = all_packages.fetch(path)
  selected[path] = entry
  %w[dependencies optionalDependencies peerDependencies].each do |kind|
    entry.fetch(kind, {}).each_key do |name|
      resolved = resolve.call(path, name)
      abort "Missing locked dependency: #{path}: #{name}" if resolved.nil? && kind == "dependencies"
      pending << resolved if resolved
    end
  end
end

lock = {
  "name" => package.fetch("name"), "version" => package.fetch("version"),
  "lockfileVersion" => upstream_lock.fetch("lockfileVersion"), "requires" => true,
  "packages" => { "" => package.reject { |key, _| %w[private type].include?(key) } }.merge(selected.sort.to_h)
}
FileUtils.mkdir_p(File.join(PROJECT, "contracts"))
File.write(File.join(PROJECT, "package.json"), JSON.pretty_generate(package) + "\n")
File.write(File.join(PROJECT, "package-lock.json"), JSON.pretty_generate(lock) + "\n")
Dir.glob(File.join(SOURCES, "upstream/contracts/*.sol")).each do |source|
  FileUtils.cp(source, File.join(PROJECT, "contracts"))
end
FileUtils.cp(File.join(__dir__, "Bootstrap.sol"), File.join(PROJECT, "contracts"))
FileUtils.cp(File.join(__dir__, "hardhat.config.js"), PROJECT)
puts "Prepared #{PROJECT} with #{selected.length} locked packages."
puts "This command does not install dependencies or compile Solidity. See docs/evm-comparison.md."
