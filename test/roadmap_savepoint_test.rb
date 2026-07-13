# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/roadmap_savepoint"

# Tests for the roadmap savepoint ledger writer added in intent 134: the machine counterpart to
# a roadmap's human `## Log`. Hermetic (tmpdir, injected clock), mirroring
# test/savepoint_ledger_test.rb's structure for the intent-dir ledger it mirrors.
class RoadmapSavepointTest < Minitest::Test
  CLI = File.expand_path("../scripts/roadmap-savepoint", __dir__)
  FIXTURE = File.expand_path("fixtures/roadmap-consistency-dividend-log.md", __dir__)

  def setup
    @home = Dir.mktmpdir("roadmap-savepoint")
    @roadmaps = File.join(@home, "roadmaps")
    FileUtils.mkdir_p(@roadmaps)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def roadmap_path(slug = "demo")
    File.join(@roadmaps, "#{slug}.md")
  end

  def write_roadmap(slug = "demo", body = "# Roadmap: Demo\n\n## Goal\ntest\n")
    path = roadmap_path(slug)
    File.write(path, body)
    path
  end

  def ledger_lines(path)
    ledger = RoadmapSavepoint.ledger_path_for(path)
    File.exist?(ledger) ? File.read(ledger).split("\n").reject(&:empty?) : []
  end

  def write_index_completed_102
    File.write(File.join(@home, "INDEX.md"), <<~IDX)
      # Index

      ## Active

      ## Future

      ## Clusters

      ## Abandoned

      ## Completed
      - [102 — Beta fix](store/102--beta/102--beta.md) — 2026-07-10 delivered via backfill test.
    IDX
  end

  # --- append -----------------------------------------------------------------

  def test_append_creates_paired_ledger_with_exact_line_shape
    path = write_roadmap
    t = Time.utc(2026, 7, 10, 2, 20, 0)
    assert_equal true, RoadmapSavepoint.append(path, "created", "demo: Demo roadmap", now: t)
    assert_equal ["2026-07-10T02:20:00Z  created  demo: Demo roadmap"], ledger_lines(path)
    assert File.exist?(File.join(@roadmaps, "demo.savepoint.md"))
  end

  def test_append_is_idempotent_on_event_detail_pair
    path = write_roadmap
    t1 = Time.utc(2026, 7, 10, 2, 20, 0)
    t2 = Time.utc(2026, 7, 10, 3, 0, 0)
    assert_equal true, RoadmapSavepoint.append(path, "dispatched", "104", now: t1)
    assert_equal false, RoadmapSavepoint.append(path, "dispatched", "104", now: t2)
    assert_equal 1, ledger_lines(path).length
  end

  def test_append_distinct_details_for_the_same_event_both_land
    path = write_roadmap
    t1 = Time.utc(2026, 7, 10, 2, 20, 0)
    t2 = Time.utc(2026, 7, 10, 3, 0, 0)
    assert_equal true, RoadmapSavepoint.append(path, "dispatched", "104", now: t1)
    assert_equal true, RoadmapSavepoint.append(path, "dispatched", "105", now: t2)
    assert_equal 2, ledger_lines(path).length
  end

  def test_append_rejects_event_outside_controlled_vocabulary
    path = write_roadmap
    assert_raises(ArgumentError) { RoadmapSavepoint.append(path, "bogus", "x", now: Time.now) }
    refute File.exist?(File.join(@roadmaps, "demo.savepoint.md"))
  end

  def test_ledger_path_for_live_roadmap
    live = File.join(@roadmaps, "demo.md")
    assert_equal File.join(@roadmaps, "demo.savepoint.md"), RoadmapSavepoint.ledger_path_for(live)
  end

  def test_ledger_path_for_archived_roadmap
    archived = File.join(@roadmaps, "archived", "demo.md")
    assert_equal File.join(@roadmaps, "archived", "demo.savepoint.md"),
                 RoadmapSavepoint.ledger_path_for(archived)
  end

  def test_append_creates_ledger_parent_directory_lazily
    archived_dir = File.join(@roadmaps, "archived")
    refute Dir.exist?(archived_dir)
    path = File.join(archived_dir, "demo.md")
    assert_equal true, RoadmapSavepoint.append(path, "closed", "demo", now: Time.utc(2026, 7, 10))
    assert File.exist?(File.join(archived_dir, "demo.savepoint.md"))
  end

  # --- rebuild (fixture: consistency-dividend Log excerpt) --------------------

  def test_rebuild_from_fixture_log_yields_exact_expected_lines
    path = File.join(@roadmaps, "consistency-dividend-log.md")
    FileUtils.cp(FIXTURE, path)
    original = File.read(path)
    write_index_completed_102

    count = RoadmapSavepoint.rebuild(path)

    expected = [
      "2026-07-10T02:20:00Z  created  Roadmap created on the owner's selection.",
      "2026-07-10T02:58:00Z  added  Added 104 to wave 2.",
      "2026-07-10T03:00:00Z  merged  101 delivered: alpha fix shipped, see store/101--alpha/outcome.md.",
      "2026-07-10T03:10:00Z  dispatched  Wave 2 activated: 104 dispatched.",
      "2026-07-10T03:20:00Z  parked  ACCOUNT SESSION LIMIT hit: team working on 105 parked mid-wrap.",
      "2026-07-10T00:00:00Z  merged  102 (from INDEX Completed)",
    ]
    assert_equal expected, ledger_lines(path)
    assert_equal expected.length, count

    # rebuild is read-only on the roadmap .md itself.
    assert_equal original, File.read(path)
  end

  def test_rebuild_never_invents_a_timestamp_for_103
    # 103 is `[x] ... — delivered` in the fixture but has no matching Log line and (in this test)
    # no INDEX Completed entry either: it must be silently dropped, never given a made-up time.
    path = File.join(@roadmaps, "consistency-dividend-log.md")
    FileUtils.cp(FIXTURE, path)
    write_index_completed_102 # backs 102 only, not 103

    RoadmapSavepoint.rebuild(path)
    lines = ledger_lines(path)
    refute lines.any? { |l| l.include?("103") }, "103 has no on-disk timestamp source and must not appear"
  end

  def test_rebuild_drops_both_102_and_103_with_no_index_at_all
    path = File.join(@roadmaps, "consistency-dividend-log.md")
    FileUtils.cp(FIXTURE, path)
    # No INDEX.md written at all in @home: neither 102 nor 103 has any backing source.
    RoadmapSavepoint.rebuild(path)
    lines = ledger_lines(path)
    refute lines.any? { |l| l.include?("102") }
    refute lines.any? { |l| l.include?("103") }
    assert_equal 5, lines.length # the five directly-classified Log lines only
  end

  def test_rebuild_is_idempotent_across_reruns
    path = File.join(@roadmaps, "consistency-dividend-log.md")
    FileUtils.cp(FIXTURE, path)
    write_index_completed_102
    RoadmapSavepoint.rebuild(path)
    first = File.read(RoadmapSavepoint.ledger_path_for(path))
    RoadmapSavepoint.rebuild(path)
    second = File.read(RoadmapSavepoint.ledger_path_for(path))
    assert_equal first, second
  end

  # --- grouping_section_body: canonical + legacy (intent 196) -------------------------

  def test_grouping_section_body_reads_canonical_batches_heading
    body = "# Roadmap: Demo\n\n## Batches\n### Batch 1\n- [x] 1 A — delivered\n"
    assert_match(/Batch 1/, RoadmapSavepoint.grouping_section_body(body))
  end

  def test_grouping_section_body_falls_back_to_legacy_waves_heading
    body = "# Roadmap: Demo\n\n## Waves\n### Wave 1\n- [x] 1 A — delivered\n"
    assert_match(/Wave 1/, RoadmapSavepoint.grouping_section_body(body))
  end

  def test_grouping_section_body_raises_naming_the_path_when_neither_heading_present
    path = write_roadmap("broken", "# Roadmap: Broken\n\n## Goal\nNo grouping heading.\n")
    err = assert_raises(RoadmapSavepoint::MissingGroupingHeading) do
      RoadmapSavepoint.grouping_section_body(File.read(path), path: path)
    end
    assert_includes err.message, path
    assert_includes err.message, "Batches"
    assert_includes err.message, "Waves"
  end

  # --- rebuild on a Batches-heading roadmap (intent 196) -------------------------------

  def test_rebuild_from_batches_heading_backfills_merged_line_from_index
    path = write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Batches
      ### Batch 1
      - [x] 901 Solo — delivered

      ## Log
      - 2026-07-10 02:20 UTC Roadmap created on the owner's selection.
    MD
    File.write(File.join(@home, "INDEX.md"), <<~IDX)
      # Index

      ## Active

      ## Future

      ## Clusters

      ## Abandoned

      ## Completed
      - [901 — Solo](store/901--solo/901--solo.md) — 2026-07-10 delivered.
    IDX

    RoadmapSavepoint.rebuild(path)
    lines = ledger_lines(path)
    assert(lines.any? { |l| l.include?("901") && l.include?("merged") })
  end

  # --- rebuild on a heading-less roadmap fails loudly (intent 196) --------------------

  def test_rebuild_raises_missing_grouping_heading_on_a_headingless_roadmap
    path = write_roadmap("broken", "# Roadmap: Broken\n\n## Goal\nNo grouping heading.\n\n## Log\n- 2026-07-10 02:20 UTC created.\n")
    assert_raises(RoadmapSavepoint::MissingGroupingHeading) { RoadmapSavepoint.rebuild(path) }
  end

  def test_cli_rebuild_missing_grouping_heading_exits_3_with_stderr_message
    path = write_roadmap("broken", "# Roadmap: Broken\n\n## Goal\nNo grouping heading.\n\n## Log\n- 2026-07-10 02:20 UTC created.\n")
    _out, err, status = run_cli(["rebuild", "--roadmap", path])
    refute status.success?
    assert_equal 3, status.exitstatus
    assert_match(/Batches/, err)
    assert_match(/Waves/, err)
  end

  # --- KEYWORD_TABLE recognizes "batch" the same way it recognizes "wave" (gate correction, D9) --

  def test_classify_log_line_recognizes_batch_the_same_way_it_recognizes_wave
    path = write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Batches
      ### Batch 1
      - [x] 902 Solo — delivered

      ## Log
      - 2026-07-10 02:20 UTC Roadmap created on the owner's selection.
      - 2026-07-10 02:30 UTC Batch 2 opened for delivery.
    MD

    RoadmapSavepoint.rebuild(path)
    lines = ledger_lines(path)
    assert(lines.any? { |l| l.include?("batch") && l.include?("Batch 2 opened for delivery.") },
           "a Batches-era grouping Log line must classify and survive rebuild, not be dropped")
  end

  def test_classify_log_line_legacy_wave_wording_still_classifies
    path = write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Waves
      ### Wave 1
      - [x] 903 Solo — delivered

      ## Log
      - 2026-07-10 02:20 UTC Roadmap created on the owner's selection.
      - 2026-07-10 02:30 UTC Wave 2 opened for delivery.
    MD

    RoadmapSavepoint.rebuild(path)
    lines = ledger_lines(path)
    assert(lines.any? { |l| l.include?("wave") && l.include?("Wave 2 opened for delivery.") },
           "the legacy Waves-era grouping Log line must keep classifying exactly as before")
  end

  # --- CLI smoke (mirrors qmd_sync_search_cli_test.rb) -------------------------

  def run_cli(args)
    Open3.capture3(RbConfig.ruby, CLI, *args)
  end

  def test_cli_append_writes_the_same_shape_as_the_lib
    path = write_roadmap
    out, _err, status = run_cli(["append", "--roadmap", path, "--event", "created", "--detail", "demo: Demo"])
    assert status.success?, "append exit 0 expected"
    assert_match(/\Aappended created  demo: Demo\n\z/, out)
    lines = ledger_lines(path)
    assert_equal 1, lines.length
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z  created  demo: Demo\z/, lines.first)
  end

  def test_cli_append_is_a_noop_on_repeat
    path = write_roadmap
    run_cli(["append", "--roadmap", path, "--event", "created", "--detail", "demo: Demo"])
    out, _err, status = run_cli(["append", "--roadmap", path, "--event", "created", "--detail", "demo: Demo"])
    assert status.success?
    assert_match(/no-op/, out)
    assert_equal 1, ledger_lines(path).length
  end

  def test_cli_rebuild_smoke_matches_lib
    path = File.join(@roadmaps, "consistency-dividend-log.md")
    FileUtils.cp(FIXTURE, path)
    write_index_completed_102
    out, _err, status = run_cli(["rebuild", "--roadmap", path])
    assert status.success?
    assert_match(/rebuilt 6 lines/, out)
    assert_equal 6, ledger_lines(path).length
  end

  def test_cli_unknown_verb_exits_nonzero
    _out, err, status = run_cli(["bogus"])
    refute status.success?
    assert_match(/unknown verb/, err)
  end

  def test_cli_append_missing_flags_exits_nonzero
    _out, err, status = run_cli(["append", "--roadmap", write_roadmap])
    refute status.success?
    assert_match(/pass --roadmap/, err)
  end
end
