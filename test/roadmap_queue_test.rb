# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/roadmap_queue"

# Tests for the deterministic roadmap reader added in intent 148: the one implementation the
# auto loop and plastic-roadmap-continuing both call. Hermetic (tmpdir, injected clock),
# mirroring test/roadmap_savepoint_test.rb's structure. No eval, no ENV or global-config seam.
class RoadmapQueueTest < Minitest::Test
  CLI = File.expand_path("../scripts/roadmap-next", __dir__)
  WAVE4_FIXTURE = File.expand_path("fixtures/roadmap-frontier-wave4.md", __dir__)
  NOW = Time.utc(2026, 7, 10, 16, 0, 0)

  def setup
    @home = Dir.mktmpdir("roadmap-queue")
    @roadmaps = File.join(@home, "roadmaps")
    FileUtils.mkdir_p(@roadmaps)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_roadmap(slug, body)
    path = File.join(@roadmaps, "#{slug}.md")
    File.write(path, body)
    path
  end

  def write_ledger(slug, lines)
    File.write(File.join(@roadmaps, "#{slug}.savepoint.md"), lines.join("\n") + "\n")
  end

  def index_line(id)
    "- [#{id} — Title](store/#{id}--slug/#{id}--slug.md) — 2026-07-10 note."
  end

  def write_index(active: [], future: [], completed: [], abandoned: [])
    lines = ["# Index", "", "## Active", ""]
    active.each { |id| lines << index_line(id) }
    lines += ["", "## Future", ""]
    future.each { |id| lines << index_line(id) }
    lines += ["", "## Clusters", "", "## Abandoned", ""]
    abandoned.each { |id| lines << index_line(id) }
    lines += ["", "## Completed", ""]
    completed.each { |id| lines << index_line(id) }
    File.write(File.join(@home, "INDEX.md"), lines.join("\n") + "\n")
  end

  def reader(mode = :queue, dir: @roadmaps, now: NOW)
    RoadmapQueue.new(roadmaps_dir: dir, now: now).public_send(mode)
  end

  def run_cli(args)
    Open3.capture3(RbConfig.ruby, CLI, *args)
  end

  # --- dispatchable --------------------------------------------------------------

  def test_dispatchable_lists_frontier_queued_entries_in_file_order
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [x] 201 Alpha — delivered

      ### Wave 2
      - [ ] 203 Gamma — queued
      - [ ] 204 Delta — queued
    MD

    result = reader
    assert_equal "dispatchable", result["state"]
    assert_equal "Wave 2", result["frontier_wave"]
    assert_equal ["203", "204"], result["dispatchable_queue"].map { |e| e["id"] }
    assert_equal [1, 2], result["dispatchable_queue"].map { |e| e["rank"] }
    assert_equal ["queued", "queued"], result["dispatchable_queue"].map { |e| e["status"] }
    assert_equal NOW.utc.iso8601, result["generated_at"]
  end

  # --- in_flight: the live wave-4/wave-5 headline case ----------------------------

  def test_in_flight_wave4_headline_case_does_not_surface_wave5_as_dispatchable
    FileUtils.cp(WAVE4_FIXTURE, File.join(@roadmaps, "consistency-dividend.md"))
    write_index(active: %w[148 133a], future: %w[85b])

    result = reader

    assert_equal "in_flight", result["state"]
    assert_equal "Wave 4", result["frontier_wave"]
    assert_empty result["dispatchable_queue"]
    refute result["dispatchable_queue"].any? { |e| e["id"] == "85b" },
      "wave 5's queued entry must never surface as dispatchable while wave 4 is live"
    assert_equal %w[148 133a], result["in_flight"].map { |e| e["id"] }
  end

  # --- exhausted / none ------------------------------------------------------------

  def test_exhausted_when_every_wave_entry_is_settled
    write_roadmap("done", <<~MD)
      # Roadmap: Done
      ## Waves
      ### Wave 1
      - [x] 501 Alpha — delivered
      - [x] 502 Beta — abandoned
    MD

    result = reader
    assert_equal "exhausted", result["state"]
    assert_empty result["dispatchable_queue"]
    assert_equal "done", result["roadmap"]
  end

  def test_none_when_roadmaps_dir_is_empty
    result = reader
    assert_equal "none", result["state"]
    assert_equal [], result["dispatchable_queue"]
    assert_nil result["roadmap"]
  end

  def test_none_when_roadmaps_dir_is_missing
    missing = File.join(@home, "does-not-exist")
    result = reader(:queue, dir: missing)
    assert_equal "none", result["state"]
    assert_equal [], result["dispatchable_queue"]
  end

  # --- blocked surfaced but not gating ----------------------------------------------

  def test_blocked_entry_is_surfaced_not_dispatchable_and_does_not_prevent_its_own_wave_from_being_frontier
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [x] 401 Solo — delivered

      ### Wave 2
      - [ ] 402 Alpha — blocked
      - [ ] 403 Beta — queued
    MD

    result = reader
    assert_equal "dispatchable", result["state"]
    assert_equal "Wave 2", result["frontier_wave"]
    assert_equal ["403"], result["dispatchable_queue"].map { |e| e["id"] }
    assert_equal ["402"], result["blocked"].map { |e| e["id"] }
  end

  def test_blocked_only_wave_is_skipped_as_frontier
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [x] 501 Solo — delivered

      ### Wave 2
      - [ ] 502 Alpha — blocked

      ### Wave 3
      - [ ] 503 Beta — queued
    MD

    result = reader
    assert_equal "dispatchable", result["state"]
    assert_equal "Wave 3", result["frontier_wave"]
    assert_equal ["503"], result["dispatchable_queue"].map { |e| e["id"] }
    assert_equal ["502"], result["blocked"].map { |e| e["id"] }
  end

  # --- delivered/abandoned settled, frontier moves on -------------------------------

  def test_wave_with_only_delivered_and_abandoned_entries_is_not_frontier
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [x] 601 Solo — delivered
      - [x] 602 Duo — abandoned

      ### Wave 2
      - [ ] 603 Trio — queued
    MD

    result = reader
    assert_equal "Wave 2", result["frontier_wave"]
    assert_equal ["603"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  # --- INDEX reconciliation wins -----------------------------------------------------

  def test_index_completed_overrides_roadmap_queued_to_settled
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [ ] 301 Solo — queued
    MD
    write_index(completed: %w[301])

    result = reader
    refute result["dispatchable_queue"].any? { |e| e["id"] == "301" }
    assert_equal "exhausted", result["state"]
  end

  def test_index_active_overrides_roadmap_delivered_to_delivering
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [x] 302 Solo — delivered
    MD
    write_index(active: %w[302])

    result = reader
    assert_equal "in_flight", result["state"]
    assert_equal ["302"], result["in_flight"].map { |e| e["id"] }
  end

  # --- tie handling ------------------------------------------------------------------

  def two_equally_live_roadmaps
    write_roadmap("alpha", <<~MD)
      # Roadmap: Alpha
      ## Waves
      ### Wave 1
      - [ ] 701 Solo — delivering
    MD
    write_roadmap("beta", <<~MD)
      # Roadmap: Beta
      ## Waves
      ### Wave 1
      - [ ] 702 Solo — delivering
    MD
  end

  def test_tie_queue_mode_breaks_deterministically_by_slug_and_reports_the_winners_frontier
    two_equally_live_roadmaps

    result = reader
    assert_equal true, result["tie"]
    assert_equal "alpha", result["roadmap"]
    assert_equal "in_flight", result["state"]
    assert_equal [], result["tie_candidates"]
  end

  def test_tie_which_mode_returns_tie_candidates_and_forces_no_winner
    two_equally_live_roadmaps

    result = reader(:which)
    assert_equal "tie", result["state"]
    assert_nil result["roadmap"]
    assert_equal 2, result["tie_candidates"].length
    result["tie_candidates"].each do |c|
      assert c.key?("roadmap")
      assert c.key?("last_event")
    end
  end

  # --- ledger read-through (R4) -------------------------------------------------------

  def test_ledger_line_wins_liveness_ranking_over_log_when_newer_and_missing_ledger_falls_back_to_log
    write_roadmap("ledger-newer", <<~MD)
      # Roadmap: Ledger newer
      ## Waves
      ### Wave 1
      - [x] 801 Solo — delivered

      ## Log
      - 2026-01-01 00:00 UTC old log line.
    MD
    write_ledger("ledger-newer", ["2026-07-10T12:00:00Z  wave  something happened"])

    write_roadmap("log-only", <<~MD)
      # Roadmap: Log only
      ## Waves
      ### Wave 1
      - [x] 802 Solo — delivered

      ## Log
      - 2026-03-01 00:00 UTC mid log line.
    MD
    # log-only intentionally has no paired .savepoint.md: falls back to ## Log.

    result = reader
    assert_equal "ledger-newer", result["roadmap"]
  end

  # --- robust entry parser accepts hyphen too, not only the em dash ------------------

  def test_entry_parser_accepts_a_hyphen_separator_as_well_as_the_em_dash
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [ ] 901 Solo - queued
    MD

    result = reader
    assert_equal ["901"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  # --- CLI smoke ------------------------------------------------------------------------

  def test_cli_reports_state_and_dispatchable_queue_as_json
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [ ] 1001 Solo — queued
    MD

    out, _err, status = run_cli(["--roadmaps-dir", @roadmaps])
    assert status.success?
    parsed = JSON.parse(out)
    assert parsed.key?("state")
    assert_kind_of Array, parsed["dispatchable_queue"]
    assert_equal "queue", parsed["mode"]
  end

  def test_cli_missing_roadmaps_dir_exits_nonzero_with_usage
    _out, err, status = run_cli([])
    refute status.success?
    assert_match(/roadmaps-dir/, err)
  end

  def test_cli_which_flag_selects_which_mode
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [ ] 1002 Solo — queued
    MD

    out, _err, status = run_cli(["--roadmaps-dir", @roadmaps, "--which"])
    assert status.success?
    parsed = JSON.parse(out)
    assert_equal "which", parsed["mode"]
  end
end
