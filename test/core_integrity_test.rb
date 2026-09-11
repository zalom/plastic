# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"
require "time"

require_relative "../scripts/lib/core_integrity"

# CoreIntegrity (intent 340, G7 n1): re-hashes the files an installed
# ~/.plastic/manifest.json lists, so the runner's own "am I running trusted
# code" check has one implementation. Matrix rows 1.13-1.17 in
# actions/ACTION_1.md n1. Hermetic: every manifest and every tracked file
# lives under a Dir.mktmpdir sandbox, never the real ~/.plastic.
class CoreIntegrityTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("core-integrity-340")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_tracked_file(name, content)
    path = File.join(@home, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def write_manifest(files)
    entries = files.each_with_object({}) { |f, h| h[f] = Digest::SHA256.file(f).hexdigest }
    File.write(File.join(@home, "manifest.json"),
               JSON.generate("version" => "1", "created" => Time.now.utc.iso8601, "files" => entries))
  end

  # --- 1.17: clean report -------------------------------------------------------

  def test_clean_manifest_reports_ok
    f = write_tracked_file("scripts/runner", "content-a")
    write_manifest([f])

    result = CoreIntegrity.check(plastic_home: @home)
    assert result[:ok], result.inspect
    assert_empty result[:drifted]
    assert_empty result[:missing]
    assert_nil result[:reason]
  end

  # --- 1.13: a drifted file is reported -----------------------------------------

  def test_drifted_file_is_reported
    f = write_tracked_file("scripts/runner", "content-a")
    write_manifest([f])
    File.write(f, "tampered content, never reviewed")

    result = CoreIntegrity.check(plastic_home: @home)
    refute result[:ok]
    assert_includes result[:drifted], f
    assert_empty result[:missing]
  end

  # --- 1.14: a missing tracked file is reported, distinct from drift -----------

  def test_missing_file_is_reported
    f = write_tracked_file("scripts/runner", "content-a")
    write_manifest([f])
    File.delete(f)

    result = CoreIntegrity.check(plastic_home: @home)
    refute result[:ok]
    assert_includes result[:missing], f
    assert_empty result[:drifted]
  end

  # --- 1.15: an absent manifest is a named refusal, never a raise --------------

  def test_absent_manifest_returns_named_reason
    result = CoreIntegrity.check(plastic_home: @home)
    refute result[:ok]
    refute_nil result[:reason]
    assert_match(/manifest/i, result[:reason])
  end

  # --- 1.16: a corrupt or unreadable manifest is a named refusal ---------------

  def test_corrupt_manifest_returns_named_reason
    File.write(File.join(@home, "manifest.json"), "{not json at all")

    result = CoreIntegrity.check(plastic_home: @home)
    refute result[:ok]
    refute_nil result[:reason]
  end

  # --- 11.16: an unreadable tracked file is reported, never raised (v1 minor 6) --

  def test_unreadable_file_is_reported_not_raised
    f = write_tracked_file("scripts/runner", "content-a")
    write_manifest([f])
    File.chmod(0o000, f)

    begin
      result = CoreIntegrity.check(plastic_home: @home)
    ensure
      File.chmod(0o644, f)
    end

    refute result[:ok]
    assert_includes result[:drifted], f
    assert_empty result[:missing]
  end
end
