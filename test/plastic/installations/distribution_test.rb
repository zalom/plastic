# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "install_fixture"
require "plastic/installations/package"
require "plastic/installations/distribution"

class DistributionTest < Plastic::TestCase
  include InstallFixture

  def distribute(mode = :install, version: "2.0.3")
    capture_io { Plastic::Installations::Distribution.new(shipped_package(version), tmp_dirs: []).public_send(mode) }.first
  end

  def manifest = JSON.parse(File.read(File.join(plastic, "manifest.json")))["files"].keys

  def test_the_core_files_reach_the_plastic_home_with_the_version_and_a_manifest_that_lists_them
    distribute

    assert_equal [File.join(plastic, "exe", "plastic"), File.join(plastic, "VERSION")],
      manifest & [File.join(plastic, "exe", "plastic"), File.join(plastic, "VERSION")]
    assert_equal "2.0.3\n", File.read(File.join(plastic, "VERSION"))
  end

  def test_a_file_the_package_does_not_ship_is_skipped
    distribute

    refute_path_exists File.join(plastic, "CHANGELOG.md")
  end

  def test_the_first_install_and_an_update_say_what_they_do
    assert_equal ["  Installing core files to #{plastic}\n", "  Core files synced (v2.0.3)\n"], distribute.lines
    assert_equal "  Updating core files to #{plastic}\n", distribute(:update).lines.first
  end

  def test_the_launchers_are_executable_even_over_a_file_that_was_not
    FileUtils.mkdir_p(File.join(plastic, "exe"))
    File.write(File.join(plastic, "exe", "plastic"), "old\n")
    File.chmod(0o644, File.join(plastic, "exe", "plastic"))
    distribute

    assert_equal [true, true], [File.executable?(File.join(plastic, "exe", "plastic")), File.executable?(File.join(plastic, "hooks", "session-start"))]
  end

  def test_a_file_the_old_manifest_listed_and_the_package_dropped_is_pruned_and_counted
    old = write(File.join(plastic, "lib", "retired.rb"), "# old\n")
    write(File.join(plastic, "manifest.json"), JSON.generate("files" => { old => "x" }))
    out = distribute(:update)

    refute_path_exists old
    assert_includes out, "  Core files synced (v2.0.3), 1 stale file(s) pruned\n"
  end

  def test_a_manifest_entry_in_the_intent_store_is_never_pruned
    kept = write(File.join(plastic, "store", "note.md"), "mine\n")
    write(File.join(plastic, "manifest.json"), JSON.generate("files" => { kept => "x" }))
    _, err = capture_io { Plastic::Installations::Distribution.new(shipped_package, tmp_dirs: []).update }

    assert_path_exists kept
    assert_includes err, "Refused to prune #{kept}: inside the intent store"
  end

  def test_the_retired_session_files_are_counted
    write(File.join(plastic, "store", ".tmp", "s1", "current"), "x")

    assert_includes distribute(:update), "  1 retired session state file(s) removed\n"
  end

  def test_the_update_check_cache_of_the_retired_hook_is_removed
    cache = write(File.join(plastic, ".cache", "update-check.json"), JSON.generate("latest" => "9.9.9"))
    distribute(:update)

    refute_path_exists cache
  end
end
