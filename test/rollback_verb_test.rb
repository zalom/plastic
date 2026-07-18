require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/rollback"

# Test subclass: overrides switch_to so behavior tests never invoke `system()` (the one
# shell-out in Rollback). This is the DI/subclass-override house rule (no eval, no
# ENV/global seam) applied to the "rollback never switches implicitly" assertions.
# Records whether switch_to was called and with what derived action.
class RecordingRollback < Rollback
  def switch_calls
    @switch_calls ||= []
  end

  def switch_to(target, current)
    switch_calls << { target: target, current: current, action: action_for(target, current) }
    0
  end
end

# rollback verb: ledger-only timeline navigation + direction-derived action (intent 30a1a),
# read-only-by-default switching gated behind an explicit --version target (intent 158a:
# the old flagless auto-switch tail and implicit bare --downgrade/--upgrade step are gone).
class RollbackVerbTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("rollback-verb")
    @v = Rollback.new(package_root: ".", plastic_home: @home, version: "x")
  end

  def teardown
    FileUtils.rm_rf(@home)
    (@extra_homes || []).each { |h| FileUtils.rm_rf(h) }
  end

  def test_timeline_is_unique_first_seen_order
    ledger = [
      { "version" => "1.0.0-alpha.15" },
      { "version" => "1.0.0-alpha.18" },
      { "version" => "1.0.0-alpha.15" }, # rolled back, already seen
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

  # --- Behavior tests: read-only-by-default surface (AC11-AC13) ---

  def fresh_recording_rollback(installed_version:, ledger_entries:)
    home = Dir.mktmpdir("rollback-verb-behavior")
    (@extra_homes ||= []) << home
    rb = RecordingRollback.new(package_root: ".", plastic_home: home, version: "x")
    ledger_entries.each { |version, action| rb.ledger_append(version, action) }
    File.write(File.join(home, "VERSION"), "#{installed_version}\n")
    rb
  end

  def test_flagless_run_never_switches_even_after_a_downgrade
    rb = fresh_recording_rollback(
      installed_version: "1.0.0-alpha.15",
      ledger_entries: [
        ["1.0.0-alpha.15", "install"],
        ["1.0.0-alpha.18", "update"],
        ["1.0.0-alpha.15", "downgrade"],
      ],
    )

    out, = capture_io { @status = rb.cli([]) }

    assert_equal 0, @status
    assert_empty rb.switch_calls, "flagless run must never call switch_to"
    assert_match(/append-only/i, out)
    refute_match(/\[y\/N\]/, out, "flagless run must never prompt")
  end

  def test_bare_downgrade_without_version_errors_and_does_not_switch
    rb = fresh_recording_rollback(
      installed_version: "1.0.0-alpha.18",
      ledger_entries: [["1.0.0-alpha.15", "install"], ["1.0.0-alpha.18", "update"]],
    )

    _, err = capture_io { @status = rb.cli(["--downgrade"]) }

    refute_equal 0, @status
    assert_empty rb.switch_calls, "bare --downgrade must never call switch_to"
    assert_match(/explicit target/i, err)
  end

  def test_bare_upgrade_without_version_errors_and_does_not_switch
    rb = fresh_recording_rollback(
      installed_version: "1.0.0-alpha.15",
      ledger_entries: [["1.0.0-alpha.15", "install"], ["1.0.0-alpha.18", "update"]],
    )

    _, err = capture_io { @status = rb.cli(["--upgrade"]) }

    refute_equal 0, @status
    assert_empty rb.switch_calls, "bare --upgrade must never call switch_to"
    assert_match(/explicit target/i, err)
  end

  def test_explicit_version_switches_with_derived_action
    rb = fresh_recording_rollback(
      installed_version: "1.0.0-alpha.18",
      ledger_entries: [["1.0.0-alpha.15", "install"], ["1.0.0-alpha.18", "update"]],
    )

    capture_io { @status = rb.cli(["--version", "1.0.0-alpha.15"]) }

    assert_equal 0, @status
    assert_equal 1, rb.switch_calls.size
    assert_equal "1.0.0-alpha.15", rb.switch_calls.first[:target]
    assert_equal "downgrade", rb.switch_calls.first[:action]
  end

  def test_downgrade_and_upgrade_flags_with_version_behave_identically_to_version_alone
    entries = [["1.0.0-alpha.15", "install"], ["1.0.0-alpha.18", "update"]]

    plain = fresh_recording_rollback(installed_version: "1.0.0-alpha.18", ledger_entries: entries)
    capture_io { plain.cli(["--version", "1.0.0-alpha.15"]) }

    with_downgrade = fresh_recording_rollback(installed_version: "1.0.0-alpha.18", ledger_entries: entries)
    capture_io { with_downgrade.cli(["--downgrade", "--version", "1.0.0-alpha.15"]) }

    with_upgrade = fresh_recording_rollback(installed_version: "1.0.0-alpha.18", ledger_entries: entries)
    capture_io { with_upgrade.cli(["--upgrade", "--version", "1.0.0-alpha.15"]) }

    assert_equal plain.switch_calls, with_downgrade.switch_calls
    assert_equal plain.switch_calls, with_upgrade.switch_calls
  end

  # AC7, falsifiable: a consolidated update (intent 210) appends ONE ledger row per
  # synced harness at the same version. version_timeline must still collapse those
  # same-version rows into a single timeline entry, or the version would appear twice.
  def test_version_timeline_dedups_same_version_multi_harness_rows
    ledger = [
      { "version" => "1.6.0", "action" => "update", "harness" => "claude" },
      { "version" => "1.6.0", "action" => "update", "harness" => "codex" },
      { "version" => "1.6.1", "action" => "update", "harness" => "claude" },
    ]
    assert_equal ["1.6.0", "1.6.1"], @v.version_timeline(ledger),
      "same-version per-harness rows must collapse to one timeline entry"
  end

  def test_unknown_version_warns_and_does_not_switch
    rb = fresh_recording_rollback(
      installed_version: "1.0.0-alpha.15",
      ledger_entries: [["1.0.0-alpha.15", "install"]],
    )

    _, err = capture_io { @status = rb.cli(["--version", "9.9.9"]) }

    refute_equal 0, @status
    assert_empty rb.switch_calls
    assert_match(/not in your version history/i, err)
  end
end
