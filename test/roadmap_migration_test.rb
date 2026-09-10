# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/roadmap_migration"

# RoadmapMigration (intent 337, n4): reads a graphless roadmap's existing
# batch order and returns the conservative edge set - every entry of batch
# N needs every entry of batch N-1, batch 1 needs nothing. Never overwrites
# a roadmap that already carries a graph (or graph-like) heading. Matrix
# rows from actions/ACTION_1.md S6/n4 (the roadmap_migration_test.rb half).
# Hermetic: every fixture lives in a Dir.mktmpdir.
class RoadmapMigrationTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("roadmap-migration")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def roadmap_path
    File.join(@dir, "demo.md")
  end

  def write_roadmap(body)
    File.write(roadmap_path, body)
  end

  def write_index(active: [], abandoned: [])
    line = ->(id) { "- [#{id} - Title](store/#{id}--slug/#{id}--slug.md) - note." }
    lines = ["# Index", "", "## Active", ""]
    active.each { |id| lines << line.call(id) }
    lines += ["", "## Future", "", "## Clusters", "", "## Abandoned", ""]
    abandoned.each { |id| lines << line.call(id) }
    lines += ["", "## Completed", ""]
    File.write(File.join(@dir, "INDEX.md"), lines.join("\n") + "\n")
  end

  def basic(batches_body, heading: "## Batches")
    <<~MD
      # Roadmap: Demo

      ## Goal
      Ship it.

      #{heading}
      #{batches_body}
      ## Log
      - 2026-01-01 00:00 UTC Opened.
    MD
  end

  # --- 4.1: batch 1 entries need nothing ---------------------------------------

  def test_first_batch_entries_need_nothing
    write_roadmap(basic(<<~B))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    B
    result = RoadmapMigration.derive(roadmap_path)
    assert_equal [], result[:edges]["101"]
    assert_equal [], result[:edges]["102"]
  end

  # --- 4.2: batch N needs EVERY entry of batch N-1 -----------------------------

  def test_batch_n_needs_every_entry_of_the_previous_batch
    write_roadmap(basic(<<~B))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued

      ### Batch 2
      - [ ] 103 Third - queued
    B
    result = RoadmapMigration.derive(roadmap_path)
    assert_equal %w[101 102], result[:edges]["103"].sort
  end

  # --- 4.3: an existing ## Graph is never overwritten, reported as skipped ----

  def test_existing_graph_is_left_untouched_and_reported_as_skipped
    body = basic(<<~B)
      ### Batch 1
      - [ ] 101 First - queued
    B
    body = body.sub("## Goal\nShip it.\n", "## Goal\nShip it.\n\n## Graph\n- 101 needs nothing\n")
    write_roadmap(body)
    result = RoadmapMigration.derive(roadmap_path)
    refute result[:ok]
    assert result[:skipped]
  end

  # --- 4.4: migrating twice changes no bytes the second time ------------------

  def test_migrating_twice_changes_no_bytes_the_second_time
    write_roadmap(basic(<<~B))
      ### Batch 1
      - [ ] 101 First - queued
    B
    result1 = RoadmapMigration.write(roadmap_path)
    content_after_first = File.read(roadmap_path)
    result2 = RoadmapMigration.write(roadmap_path)
    assert result1[:written]
    refute result2[:written]
    assert_equal content_after_first, File.read(roadmap_path)
  end

  # --- 4.5: the derived graph is cycle checked before write -------------------

  def test_derived_graph_is_cycle_checked_before_write
    # 101 appears in both batch 1 and batch 3: batch 2's 102 needs 101 (as a
    # batch-1 member), but 101's OWN derived needs (from its batch-3
    # occurrence) become batch 2's members - 101 needs 102, 102 needs 101.
    write_roadmap(basic(<<~B))
      ### Batch 1
      - [ ] 101 First - queued

      ### Batch 2
      - [ ] 102 Second - queued

      ### Batch 3
      - [ ] 101 First - queued
    B
    result = RoadmapMigration.derive(roadmap_path)
    refute result[:ok]
    refute_nil result[:reason]
  end

  # --- 4.6: derives from a legacy ## Waves heading -----------------------------

  def test_waves_heading_derives_the_same_edges_as_batches
    write_roadmap(basic(<<~B, heading: "## Waves"))
      ### Wave 1
      - [ ] 101 First - queued

      ### Wave 2
      - [ ] 102 Second - queued
    B
    result = RoadmapMigration.derive(roadmap_path)
    assert result[:ok]
    assert_equal [], result[:edges]["101"]
    assert_equal ["101"], result[:edges]["102"]
  end

  # --- 4.7: a single-batch roadmap derives all roots ---------------------------

  def test_single_batch_roadmap_derives_all_roots
    write_roadmap(basic(<<~B))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    B
    result = RoadmapMigration.derive(roadmap_path)
    assert result[:ok]
    assert_equal [], result[:edges]["101"]
    assert_equal [], result[:edges]["102"]
  end

  # --- 4.8: a delivered entry still appears as a need --------------------------

  def test_delivered_entries_still_appear_as_needs
    write_roadmap(basic(<<~B))
      ### Batch 1
      - [x] 101 First - delivered

      ### Batch 2
      - [ ] 102 Second - queued
    B
    result = RoadmapMigration.derive(roadmap_path)
    assert_equal ["101"], result[:edges]["102"]
  end

  # --- 4.15: refuse a roadmap carrying a graph-like heading --------------------

  def test_migrate_refuses_a_roadmap_carrying_a_graph_like_heading
    body = basic(<<~B)
      ### Batch 1
      - [ ] 101 First - queued
    B
    body = body.sub("## Goal\nShip it.\n", "## Goal\nShip it.\n\n## Graph (superseded 2026-09-01)\nold notes\n")
    write_roadmap(body)
    result = RoadmapMigration.derive(roadmap_path)
    refute result[:ok]
    assert result[:skipped]
  end

  # --- 4.16: an id in two batches yields one edge line -------------------------

  def test_id_listed_in_two_batches_yields_one_edge_line
    write_roadmap(basic(<<~B))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued

      ### Batch 2
      - [ ] 101 First - queued
    B
    result = RoadmapMigration.derive(roadmap_path)
    # 101's needs come from its LAST (batch 2) occurrence: batch 1's members.
    assert_equal 1, result[:edges].keys.count { |id| id == "101" }
    assert_equal %w[101 102], result[:edges]["101"].sort
  end

  # --- 4.17: an abandoned entry is not derived as a need -----------------------

  def test_abandoned_entry_is_not_derived_as_a_need
    write_roadmap(basic(<<~B))
      ### Batch 1
      - [ ] 101 First - abandoned
      - [ ] 102 Second - queued

      ### Batch 2
      - [ ] 103 Third - queued
    B
    result = RoadmapMigration.derive(roadmap_path)
    refute_includes result[:edges]["103"], "101"
    assert_includes result[:edges]["103"], "102"
  end
end
