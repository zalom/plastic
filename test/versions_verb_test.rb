require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/versions"

# versions verb: ledger-only timeline navigation + direction-derived action (intent 30a1a).
class VersionsVerbTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("versions-verb")
    @v = Versions.new(package_root: ".", plastic_home: @home, version: "x")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_timeline_is_unique_first_seen_order
    ledger = [
      { "version" => "1.0.0-alpha.15" },
      { "version" => "1.0.0-alpha.18" },
      { "version" => "1.0.0-alpha.15" }, # rolled back — already seen
    ]
    assert_equal ["1.0.0-alpha.15", "1.0.0-alpha.18"], @v.version_timeline(ledger)
  end

  def test_step_back_and_forward
    tl = ["1.0.0-alpha.15", "1.0.0-alpha.18"]
    assert_equal "1.0.0-alpha.15", @v.step_target(tl, "1.0.0-alpha.18", :back)
    assert_equal "1.0.0-alpha.18", @v.step_target(tl, "1.0.0-alpha.15", :forward)
  end

  def test_step_past_the_edges_returns_nil
    tl = ["1.0.0-alpha.15", "1.0.0-alpha.18"]
    assert_nil @v.step_target(tl, "1.0.0-alpha.15", :back)
    assert_nil @v.step_target(tl, "1.0.0-alpha.18", :forward)
  end

  def test_action_is_derived_from_direction
    assert_equal "downgrade", @v.action_for("1.0.0-alpha.15", "1.0.0-alpha.18")
    assert_equal "update", @v.action_for("1.0.0-alpha.18", "1.0.0-alpha.15")
  end

  def test_empty_ledger_is_handled
    out, = capture_io { @status = @v.cli([]) }
    assert_equal 0, @status
    assert_match(/No version history/i, out)
  end

  def test_table_print_marks_current
    @v.ledger_append("1.0.0-alpha.15", "install")
    @v.ledger_append("1.0.0-alpha.18", "update")
    File.write(File.join(@home, "VERSION"), "1.0.0-alpha.18\n")
    out, = capture_io { @v.cli([]) }
    assert_match(/1\.0\.0-alpha\.18/, out)
    assert_match(/append-only/i, out)
  end
end
