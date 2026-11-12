# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require_relative "support/child_process"
require "rubygems/package"
require "tmpdir"
require "zlib"
require_relative "../bin/lib/release_build"

class ReleaseBuildTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def setup
    @dir = Dir.mktmpdir("plastic-release-build")
    @root = File.join(@dir, "checkout")
    @out = File.join(@dir, "release")
    write_checkout
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_the_archive_holds_the_listed_files_and_the_version_under_package
    ReleaseBuild.call(version: "2.0.4-alpha.1", directory: @out, root: @root)

    assert_equal %w[package/LICENSE package/PLASTIC.md package/README.md package/VERSION package/bin/plastic package/exe/plastic package/package.json],
      entries.keys.sort
    assert_equal "2.0.4-alpha.1\n", entries.fetch("package/VERSION").first
  end

  def test_the_archive_keeps_the_launcher_executable
    ReleaseBuild.call(version: "2.0.4", directory: @out, root: @root)

    assert_equal 0o755, entries.fetch("package/bin/plastic").last
    assert_equal 0o755, entries.fetch("package/exe/plastic").last
  end

  def test_the_checksum_file_names_the_archive_by_its_sha256
    ReleaseBuild.call(version: "2.0.4", directory: @out, root: @root)

    assert_equal "#{Digest::SHA256.file(archive).hexdigest}  plastic.tgz\n", File.read("#{archive}.sha256")
  end

  def test_the_manifest_names_the_release_and_the_archive
    ReleaseBuild.call(version: "2.0.4-beta.2", directory: @out, root: @root)

    release = manifest.fetch("release")

    assert_equal ["v2.0.4-beta.2", "beta", "universal", "universal"], release.values_at("tag", "channel", "platform", "architecture")
    assert_equal Digest::SHA256.file(archive).hexdigest, manifest.dig("archive", "sha256")
  end

  def test_the_manifest_carries_the_ruby_pins_of_install_sh
    ReleaseBuild.call(version: "2.0.4", directory: @out, root: @root)

    assert_equal InstallerRelease::RubyPins.read, manifest.dig("ruby", "builds")
  end

  def test_seal_writes_the_ruby_pins_it_is_given
    FileUtils.mkdir_p(@out)
    File.binwrite(archive, "archive bytes")
    ReleaseBuild.seal("2.0.3", @out, pins: { "arm64-darwin" => { "key" => "k" } })

    assert_equal({ "arm64-darwin" => { "key" => "k" } }, manifest.dig("ruby", "builds"))
  end

  def test_seal_writes_the_checksum_and_manifest_for_an_archive_built_elsewhere
    FileUtils.mkdir_p(@out)
    File.binwrite(archive, "archive bytes")
    ReleaseBuild.seal("2.0.3", @out)

    assert_equal ["v2.0.3", "latest"], manifest.fetch("release").values_at("tag", "channel")
    assert_equal "#{Digest::SHA256.hexdigest("archive bytes")}  plastic.tgz\n", File.read("#{archive}.sha256")
  end

  def test_the_command_builds_the_three_release_files
    _out, err, status = ChildProcess.capture3("ruby", File.join(REPO, "bin", "build-release"), "--version", "2.0.4",
      "--directory", @out, "--root", @root)

    assert_predicate status, :success?, err
    assert_equal %w[plastic.manifest.json plastic.tgz plastic.tgz.sha256], Dir.children(@out).sort
  end

  def test_the_command_refuses_a_call_without_a_version
    _out, err, status = ChildProcess.capture3("ruby", File.join(REPO, "bin", "build-release"), "--directory", @out)

    assert_equal 1, status.exitstatus
    assert_includes err, "--version"
  end

  def test_the_archive_of_the_tree_ships_the_launcher_and_the_readers_files_and_no_release_tool
    ReleaseBuild.call(version: "2.0.4", directory: @out, root: REPO)
    names = entries.keys

    assert_empty(%w[package/exe/plastic package/lib/plastic.rb package/scripts/install-release package/scripts/select-update-target
      package/scripts/lib/release_channels.rb package/bin/plastic] - names)
    assert_empty(names.grep(/build-release|release-check|release_build\.rb|release_archive\.rb|release_guard\.rb/))
    assert_empty(names.grep(%r{\Apackage/bin/}) - ["package/bin/plastic"])
  end

  def test_the_entry_of_a_release_built_from_the_tree_starts_the_way_install_sh_runs_it
    share = unpacked_share
    out, err, status = ChildProcess.capture3({ "HOME" => @dir }, RbConfig.ruby, File.join(share, "bin", "plastic"), "version", "--json")

    assert_equal 0, status.exitstatus, err
    assert_kind_of Hash, JSON.parse(out)
  end

  def test_the_entry_of_a_release_built_from_the_tree_is_executable_after_unpacking
    assert_equal 0o755, File.stat(File.join(unpacked_share, "bin", "plastic")).mode & 0o777
  end

  private

  def unpacked_share
    ReleaseBuild.call(version: "2.0.4", directory: @out, root: REPO)
    share = File.join(@dir, "share")
    FileUtils.mkdir_p(share)
    _out, err, status = ChildProcess.capture3("tar", "-xzf", archive, "--strip-components=1", "-C", share)

    assert_predicate status, :success?, err
    share
  end

  def archive = File.join(@out, "plastic.tgz")

  def manifest = JSON.parse(File.read(File.join(@out, "plastic.manifest.json")))

  def entries
    Zlib::GzipReader.open(archive) do |gzip|
      Gem::Package::TarReader.new(gzip).to_h { |entry| [entry.full_name, [entry.read, entry.header.mode & 0o777]] }
    end
  end

  def write_checkout
    FileUtils.mkdir_p(File.join(@root, "exe"))
    File.write(File.join(@root, "package.json"), JSON.generate("version" => "2.0.4", "files" => %w[exe/ PLASTIC.md VERSION]))
    %w[README.md LICENSE PLASTIC.md].each { |name| File.write(File.join(@root, name), "#{name}\n") }
    File.write(File.join(@root, "exe", "plastic"), "#!/bin/sh\n")
    File.chmod(0o755, File.join(@root, "exe", "plastic"))
  end
end
