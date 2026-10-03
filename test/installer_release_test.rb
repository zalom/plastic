# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "fileutils"
require "json"
require "rubygems/package"
require "tmpdir"
require "zlib"

require_relative "../scripts/lib/installer_release"

class InstallerReleaseTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("plastic-installer-release")
    @archive = archive_with(version: "2.0.3")
    @manifest = InstallerRelease::Manifest.build(
      archive: @archive,
      release: release,
      ruby_requirement: ">= 4.0.0"
    )
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_manifest_binds_the_archive_to_its_release_identity
    InstallerRelease::Manifest.validate!(@manifest, archive: @archive, expected_release: release)

    assert_equal Digest::SHA256.file(@archive).hexdigest, @manifest.fetch("archive").fetch("sha256")
    assert_equal "v2.0.3", @manifest.fetch("release").fetch("tag")
  end

  def test_manifest_rejects_a_mismatched_archive_before_staging
    File.binwrite(@archive, "corrupt archive")

    error = assert_raises(InstallerRelease::VerificationError) do
      InstallerRelease::Manifest.validate!(@manifest, archive: @archive, expected_release: release)
    end

    assert_match(/checksum/, error.message)
  end

  def test_archive_inspection_rejects_parent_paths_before_extraction
    unsafe = File.join(@root, "unsafe.tgz")
    tar_path = File.join(@root, "unsafe.tar")
    File.open(tar_path, "wb") do |tar_file|
      Gem::Package::TarWriter.new(tar_file) { |tar| tar.add_file("../escape", 0o644) { |file| file.write("unsafe") } }
    end
    Zlib::GzipWriter.open(unsafe) do |gzip|
      gzip.write(File.binread(tar_path))
    end

    assert_raises(InstallerRelease::ArchiveError) { InstallerRelease::Archive.new(unsafe).inspect! }
  end

  def test_stage_extracts_only_a_valid_candidate_inside_a_unique_staging_directory
    stage = InstallerRelease::Staging.create!(archive: @archive, manifest: @manifest, parent: @root)

    assert_path_exists File.join(stage, "bin", "plastic")
    assert_equal "2.0.3", File.read(File.join(stage, "VERSION")).strip
    assert File.dirname(stage).start_with?(@root)
  end

  def test_activation_keeps_a_previous_working_version_and_rolls_back
    home = File.join(@root, "home", ".plastic")
    first = staged_candidate("2.0.2")
    second = staged_candidate("2.0.3")
    installer = InstallerRelease::Activation.new(home: home)

    installer.activate!(first, version: "2.0.2")
    installer.activate!(second, version: "2.0.3")

    assert_equal "2.0.3", installer.active_version
    assert_equal "2.0.2", installer.previous_version

    installer.rollback!

    assert_equal "2.0.2", installer.active_version
    assert_equal "2.0.3", installer.previous_version
  end

  def test_activation_failure_leaves_the_old_active_candidate_usable
    home = File.join(@root, "home", ".plastic")
    installer = InstallerRelease::Activation.new(home: home)
    installer.activate!(staged_candidate("2.0.2"), version: "2.0.2")

    error = assert_raises(InstallerRelease::ActivationError) do
      installer.activate!(staged_candidate("2.0.3"), version: "2.0.3", before_switch: -> { raise "injected failure" })
    end

    assert_match(/injected failure/, error.message)
    assert_equal "2.0.2", installer.active_version
    assert_equal "old", File.read(File.join(installer.active_path, "bin", "plastic")).strip
  end

  private

  def release
    { "tag" => "v2.0.3", "version" => "2.0.3", "channel" => "latest", "platform" => "darwin", "architecture" => "arm64" }
  end

  def archive_with(version:)
    source = File.join(@root, "source-#{version}")
    FileUtils.mkdir_p(File.join(source, "package", "bin"))
    File.write(File.join(source, "package", "VERSION"), "#{version}\n")
    File.write(File.join(source, "package", "bin", "plastic"), "#!/bin/sh\necho #{version}\n")
    File.chmod(0o755, File.join(source, "package", "bin", "plastic"))
    archive = File.join(source, "plastic.tgz")
    system("tar", "-czf", archive, "-C", source, "package", exception: true)
    archive
  end

  def staged_candidate(version)
    stage = File.join(@root, "stage-#{version}")
    FileUtils.mkdir_p(File.join(stage, "bin"))
    File.write(File.join(stage, "VERSION"), "#{version}\n")
    File.write(File.join(stage, "bin", "plastic"), (version == "2.0.2") ? "old\n" : "new\n")
    File.chmod(0o755, File.join(stage, "bin", "plastic"))
    stage
  end
end
