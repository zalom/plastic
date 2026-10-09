# frozen_string_literal: true

require "digest"
require "json"
require_relative "../../../scripts/lib/installer_release"
require_relative "../../test_helper"

# A throwaway package, home and agent folder for the installer commands.
module InstallerHelper
  PACKAGE_ROOT = File.expand_path("../../..", __dir__)

  def call(*argv, env: {}) = plastic(*argv, env:, table: Plastic::CLI::TABLE)

  def package_version = JSON.parse(File.read(File.join(PACKAGE_ROOT, "package.json"))).fetch("version")

  def fake_package(version)
    root = File.join(@home, "package")
    FileUtils.mkdir_p(root)
    File.write(File.join(root, "package.json"), JSON.generate("version" => version))
    root
  end

  def installed(version, ledger: [])
    FileUtils.mkdir_p(@plastic_home)
    File.write(File.join(@plastic_home, "VERSION"), "#{version}\n")
    lines = ledger.map { |number| JSON.generate("version" => number, "action" => "install", "at" => "2026-10-03T12:00:00+02:00") }
    File.write(File.join(@plastic_home, "versions.json"), lines.map { |line| "#{line}\n" }.join)
  end

  def share = File.join(@home, ".local", "share", "plastic")

  def activation = InstallerRelease::Activation.new(home: share)

  def activated(*versions)
    versions.each { |version| activation.activate(release_package(File.join(@home, "stage-#{version}"), version), version: version) }
  end

  def release_package(path, version)
    FileUtils.mkdir_p(File.join(path, "bin"))
    File.write(File.join(path, "VERSION"), "#{version}\n")
    File.write(File.join(path, "bin", "plastic"), recording_launcher(version))
    File.chmod(0o755, File.join(path, "bin", "plastic"))
    path
  end

  def recording_launcher(version) = <<~RUBY
    #!/usr/bin/env ruby
    if ARGV == %w[version --json]
      puts '{"result":{"version":"#{version}"}}'
      exit
    end
    File.open(File.join(Dir.home, "launcher-calls"), "a") { |calls| calls.puts(ARGV.join(" ")) }
    puts "#{version}"
  RUBY

  def local_release(version)
    directory = File.join(@home, "release-#{version}")
    release_package(File.join(directory, "package"), version)
    archive = File.join(directory, "plastic.tgz")
    system("tar", "-czf", archive, "-C", directory, "package", exception: true)
    identity = InstallerRelease::Manifest.identity(version).merge("platform" => "universal", "architecture" => "universal")
    InstallerRelease::Manifest.write(File.join(directory, "plastic.manifest.json"), archive: archive, release: identity)
    File.write(File.join(directory, "plastic.tgz.sha256"), "#{Digest::SHA256.file(archive).hexdigest}  plastic.tgz\n")
    directory
  end

  def launcher_calls = File.exist?(File.join(@home, "launcher-calls")) ? File.readlines(File.join(@home, "launcher-calls"), chomp: true) : []

  def installed_home_without_stores
    FileUtils.mkdir_p(File.join(@home, ".claude"))
    call("install", "--claude")
    Plastic::Graph::Database::ConnectionPool.release(@home)
    FileUtils.rm_rf(File.join(@plastic_home, "stores"))
  end

  def claude_folder = FileUtils.mkdir_p(File.join(@home, ".claude")).first

  def tree_snapshot(path)
    return [] unless Dir.exist?(path)

    Dir.chdir(path) do
      Dir.glob("**/*", File::FNM_DOTMATCH).reject { |entry| entry.end_with?(".") }.sort.map do |entry|
        File.file?(entry) ? [entry, File.binread(entry)] : [entry, :directory]
      end
    end
  end
end
