# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseRubyStageTest < Minitest::Test
  include ReleaseHelper

  PIN = { "root" => "ruby-4.0.7", "version" => "4.0.7", "key" => "darwin-arm64", "sha256" => "ab" * 32 }.freeze

  def teardown
    FileUtils.chmod_R("u+w", @root)
    super
  end

  def folder = File.join(@root, "rubies", "4.0.7")

  def archive = tar_archive("ruby.tgz") { |tar| tar.add_file_simple("ruby-4.0.7/bin/ruby", 0o755, 3) { |io| io.write("rb\n") } }

  def unpack(printed)
    FileUtils.mkdir_p([File.join(@root, "stage"), File.dirname(folder)])
    asked = []
    run = ->(ruby) { (asked << ruby) && printed }
    InstallerRelease::RubyStage.new(File.join(@root, "stage"), PIN, run).unpack(archive, folder)
    asked
  end

  def test_a_ruby_that_starts_is_moved_into_its_folder_and_marked
    unpack("4.0.7")

    assert_equal "#{PIN.fetch("sha256")}\n", File.read(File.join(folder, InstallerRelease::Rubies::MARKER))
  end

  def test_the_ruby_is_started_from_the_staging_folder
    assert_equal [File.join(@root, "stage", "unpacked", "ruby-4.0.7", "bin", "ruby")], unpack("4.0.7")
  end

  def test_the_moved_ruby_is_read_only
    unpack("4.0.7")

    refute File.writable?(folder)
  end

  def test_a_ruby_that_prints_another_version_is_refused
    error = assert_raises(InstallerRelease::VerificationError) { unpack("dyld: missing library\n") }

    assert_equal ["the Ruby darwin-arm64 does not start: dyld: missing library", false], [error.message, File.exist?(folder)]
  end
end
