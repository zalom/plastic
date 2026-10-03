# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "fileutils"
require "rubygems/package"
require "tmpdir"
require "zlib"

require_relative "../../scripts/lib/installer_release"

# Builds release archives, staged candidates and installation homes inside
# one throwaway directory per test.
module ReleaseHelper
  RELEASE = { "tag" => "v2.0.3", "version" => "2.0.3", "channel" => "latest", "platform" => "darwin",
              "architecture" => "arm64" }.freeze

  def setup
    @root = Dir.mktmpdir("plastic-installer-release")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # Stands in for the home sync: writes two home files, then raises what a
  # test asks for, such as an Interrupt for a process that stops halfway.
  class SyncDouble
    attr_accessor :failure
    attr_reader :seen

    def initialize(root, activation_home)
      @root = root
      @activation_home = activation_home
      @seen = []
    end

    def paths = [File.join(@root, "PLASTIC.md"), File.join(@root, "added.md")]

    def call
      @seen << InstallerRelease::Activation.new(home: @activation_home).active_version
      File.write(paths.first, "changed\n")
      File.write(paths.last, "added\n")
      raise failure if failure
    end
  end

  def release = RELEASE

  def install_home = File.join(@root, "home", ".plastic")

  def archive_with(version: "2.0.3")
    source = File.join(@root, "source-#{version}")
    package = File.join(source, "package")
    write_package(package, version, "#!/bin/sh\necho #{version}\n")
    archive = File.join(source, "plastic.tgz")
    system("tar", "-czf", archive, "-C", source, "package", exception: true)
    archive
  end

  def manifest_for(archive) = InstallerRelease::Manifest.build(archive: archive, release: release)

  def release_files(version: "2.0.3")
    archive = archive_with(version: version)
    directory = File.dirname(archive)
    identity = InstallerRelease::Manifest.identity(version).merge("platform" => "darwin", "architecture" => "arm64")
    InstallerRelease::Manifest.write(File.join(directory, "plastic.manifest.json"), archive: archive, release: identity)
    File.write(File.join(directory, "plastic.tgz.sha256"), "#{Digest::SHA256.file(archive).hexdigest}  plastic.tgz\n")
    directory
  end

  def tar_archive(name = "entries.tgz")
    path = File.join(@root, name)
    Zlib::GzipWriter.open(path) { |gzip| Gem::Package::TarWriter.new(gzip) { |tar| yield tar } }
    path
  end

  def staged_candidate(version)
    stage = File.join(@root, "stage-#{version}")
    write_package(stage, version, (version == "2.0.2") ? "old\n" : "new\n")
    stage
  end

  def activation_with(*installed, activation: InstallerRelease::Activation.new(home: install_home))
    installed.each { |version| activation.activate(staged_candidate(version), version: version) }
    activation
  end

  def versions(installer) = [installer.active_version, installer.previous_version]

  def write_package(path, version, launcher)
    FileUtils.mkdir_p(File.join(path, "bin"))
    File.write(File.join(path, "VERSION"), "#{version}\n")
    File.write(File.join(path, "bin", "plastic"), launcher)
    File.chmod(0o755, File.join(path, "bin", "plastic"))
  end
end
