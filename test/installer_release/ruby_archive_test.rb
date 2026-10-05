# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseRubyArchiveTest < Minitest::Test
  include ReleaseHelper

  def archive = tar_archive("ruby.tgz") { |tar| tar.add_file_simple("ruby-4.0.7/bin/ruby", 0o755, 3) { |io| io.write("rb\n") } }

  def pin_for(path, **changes)
    { "size" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest }.merge(changes.transform_keys(&:to_s))
  end

  def test_an_archive_that_matches_its_pin_lists_its_entries
    path = archive

    assert_equal ["ruby-4.0.7/bin/ruby"], InstallerRelease::RubyArchive.new(path, pin_for(path)).check
  end

  def test_an_archive_of_another_size_is_refused
    path = archive

    error = assert_raises(InstallerRelease::VerificationError) { InstallerRelease::RubyArchive.new(path, pin_for(path, size: 1)).check }
    assert_equal "the Ruby archive has #{File.size(path)} bytes, not the pinned 1", error.message
  end

  def test_an_archive_with_another_digest_is_refused
    path = archive

    error = assert_raises(InstallerRelease::VerificationError) { InstallerRelease::RubyArchive.new(path, pin_for(path, sha256: "0" * 64)).check }
    assert_equal "the Ruby archive does not match its pinned SHA-256", error.message
  end
end
