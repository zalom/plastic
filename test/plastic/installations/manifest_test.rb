# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/manifest"

class ManifestTest < Plastic::TestCase
  Manifest = Plastic::Installations::Manifest

  def manifest = Manifest.new(File.join(@home, "manifest.json"))

  def listed(*names)
    names.map { |name| File.join(@home, name) }.each { |path| File.write(path, "text of #{File.basename(path)}") }.then { |paths| manifest.write(paths, FixedClock::AT) && paths }
  end

  def test_a_manifest_carries_local_time_with_its_offset
    manifest.write([], Time.new(2026, 10, 5, 10, 0, 0, "+02:00"))

    assert_equal "2026-10-05T10:00:00+02:00", JSON.parse(File.read(File.join(@home, "manifest.json")))["created"]
  end

  def test_a_written_manifest_lists_the_files_that_exist_with_their_hashes
    paths = listed("a.md", "b.md")
    manifest.write(paths + [File.join(@home, "absent.md")], FixedClock::AT)

    assert_equal paths, manifest.files
  end

  def test_a_missing_or_broken_manifest_lists_no_files
    File.write(File.join(@home, "manifest.json"), "{ broken")

    assert_equal [[], true], [manifest.files, manifest.empty?]
  end

  def test_a_manifest_verifies_when_every_listed_file_matches_its_hash
    listed("a.md")

    assert_predicate manifest, :verified?
  end

  def test_a_changed_file_fails_the_verification
    File.write(listed("a.md").first, "changed")

    refute_predicate manifest, :verified?
  end

  def test_a_manifest_with_no_files_or_no_file_fails_the_verification
    refute_predicate manifest, :verified?
    manifest.write([], FixedClock::AT)

    refute_predicate manifest, :verified?
  end
end
