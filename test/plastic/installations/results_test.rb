# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/results"

class ResultsTest < Plastic::TestCase
  def printed(results, mode: :install, version: "2.0.3")
    capture_io { Plastic::Installations::Results.new(version).print(results, mode) }.first
  end

  def ok(agent = "Claude Code", **more) = { agent:, success: true, files: 4, from_version: nil, to_version: "2.0.3", **more }

  def test_an_installed_agent_says_how_many_files_and_the_run_ends_with_no_next_step_of_its_own
    out = printed([ok])

    assert_includes out, "  Claude Code: 4 files installed\n"
    assert_includes out, "\nPlastic v2.0.3 installed.\n"
    refute_match(/next/i, out)
  end

  def test_a_failed_agent_has_a_failed_row_in_the_summary_table
    out = printed([ok, { agent: "Codex CLI", success: false, reason: "no folder" }])

    assert_match(/Codex CLI\s+- -> -\s+failed/, out)
  end

  def test_an_update_says_re_synced
    assert_includes printed([ok], mode: :update), "\nPlastic v2.0.3 re-synced.\n"
  end

  def test_a_failed_agent_gets_its_reason_on_its_own_line
    out = printed([{ agent: "Codex CLI", success: false, reason: "no folder" }])

    assert_includes out, "   Codex CLI: no folder\n"
  end

  def test_an_agent_left_alone_says_how_to_sync_it
    out = printed([{ agent: "Hermes", success: true, skipped: true }])

    assert_includes out, "  Hermes: already registered, not re-synced (use --reinstall to re-sync)\n"
  end

  def test_two_results_get_a_summary_table
    out = printed([ok, ok("Hermes", from_version: "2.0.2")])

    assert_includes out, "  Agent          From -> To           Result\n"
    assert_includes out, "  Hermes         2.0.2 -> 2.0.3    ok" + "\n"
  end

  def test_the_codex_trust_reminder_names_the_changed_hooks_and_is_absent_when_none_changed
    assert_includes printed([ok("Codex CLI", changed_hooks: ["hook end", "hook start"])],
      mode: :update), "   Codex: open Codex, run /hooks, and trust the changed Plastic hooks: hook end, hook start.\n   Plastic's hooks will not fire until you do.\n"
    refute_includes printed([ok("Codex CLI", changed_hooks: [])]), "trust the changed"
  end

  def test_every_line_is_plain_ascii
    out = printed([ok, ok("Hermes", from_version: "2.0.2"), { agent: "Zed", success: true, skipped: true }, { agent: "Codex CLI", success: false, reason: "no folder" }])

    assert_predicate out, :ascii_only?
  end
end
