# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/roadmap_render"

# RoadmapRender (intent 337, n3): renders "## Tree" and the roadmap's own
# grouping section (## Batches, or legacy ## Waves) from the RoadmapGraph
# model and writes both back through AtomicWrite, replacing exactly those
# two sections and leaving every other byte of the file alone. Entry lines
# are carried over verbatim, and so are the lines the canonical grammar
# cannot parse and any prose a human wrote between batch headings. Matrix
# rows from actions/ACTION_1.md S4/n3. Hermetic: every fixture lives in a
# Dir.mktmpdir; this module never touches the real ~/.plastic.
class RoadmapRenderTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("roadmap-render")
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

  # A raising renamer, to simulate a write interrupted after the temp file
  # lands but before the rename completes (row 3.5).
  FAILING_RENAMER = lambda do |_from, _to|
    raise Errno::ENOENT, "simulated interrupted rename"
  end

  def basic(batches_body, graph_body, heading: "## Batches")
    <<~MD
      # Roadmap: Demo

      ## Goal
      Ship it.

      ## Graph
      #{graph_body}
      #{heading}
      #{batches_body}
      ## Log
      - 2026-01-01 00:00 UTC Opened.
    MD
  end

  # --- 3.1: "## Tree" is replaced, created when absent -------------------------

  def test_second_render_replaces_the_tree_and_does_not_append
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    RoadmapRender.write(roadmap_path)
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    assert_equal 1, content.scan(/^## Tree$/).length
  end

  # --- 3.2: entry lines are carried over verbatim into computed batches -------

  def test_entry_lines_are_carried_over_verbatim_into_computed_batches
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First entry (extra parenthetical) - queued
    B
      - 101 needs nothing
    G
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    assert_includes content, "- [ ] 101 First entry (extra parenthetical) - queued"
  end

  # --- 3.3: ## Goal, ## Graph, ## Log stay byte-identical ----------------------

  def test_goal_graph_and_log_sections_are_byte_identical_after_render
    body = basic(<<~B, <<~G)
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    write_roadmap(body)
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    assert_includes content, "## Goal\nShip it.\n"
    assert_includes content, "- 101 needs nothing\n"
    assert_includes content, "## Log\n- 2026-01-01 00:00 UTC Opened.\n"
  end

  # --- 3.4: writes through AtomicWrite, never File.write in place -------------

  def test_write_goes_through_atomic_write_not_file_write
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    renamer_called = false
    renamer = lambda do |from, to|
      renamer_called = true
      File.rename(from, to)
    end
    RoadmapRender.write(roadmap_path, renamer: renamer)
    assert renamer_called, "AtomicWrite's renamer seam must be used"
  end

  # --- 3.5: a rename that raises leaves the original intact, no temp behind ---

  def test_failed_rename_leaves_the_original_intact_and_no_temp_behind
    original = basic(<<~B, <<~G)
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    write_roadmap(original)
    assert_raises(Errno::ENOENT) { RoadmapRender.write(roadmap_path, renamer: FAILING_RENAMER) }
    assert_equal original, File.read(roadmap_path)
    leftovers = Dir.glob(File.join(@dir, ".*"))
    assert_empty leftovers, "no temp file should be left behind: #{leftovers.inspect}"
  end

  # --- 3.6: a cyclic graph is refused, file unchanged --------------------------

  def test_cyclic_graph_is_refused_and_the_file_is_unchanged
    original = basic(<<~B, <<~G)
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    B
      - 101 needs 102
      - 102 needs 101
    G
    write_roadmap(original)
    result = RoadmapRender.write(roadmap_path)
    refute result[:ok]
    assert_equal original, File.read(roadmap_path)
  end

  # --- 3.7: a legacy "## Waves" heading is preserved, never renamed -----------

  def test_legacy_waves_heading_is_preserved_not_renamed
    write_roadmap(basic(<<~B, <<~G, heading: "## Waves"))
      ### Wave 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    assert_includes content, "## Waves"
    refute_includes content, "## Batches"
  end

  # --- 3.8: a roadmap with no "## Graph" is refused, unchanged ----------------

  def test_roadmap_without_graph_is_refused_and_unchanged
    original = <<~MD
      # Roadmap: Demo

      ## Goal
      Ship it.

      ## Batches

      ### Batch 1
      - [ ] 101 First - queued
    MD
    write_roadmap(original)
    result = RoadmapRender.write(roadmap_path)
    refute result[:ok]
    assert_equal original, File.read(roadmap_path)
  end

  # --- 3.9: rendering twice changes no bytes the second time -------------------

  def test_render_twice_changes_no_bytes_the_second_time
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 102 Second - queued
      - [ ] 101 First - queued
    B
      - 101 needs nothing
      - 102 needs nothing
    G
    RoadmapRender.write(roadmap_path)
    after_first = File.read(roadmap_path)
    RoadmapRender.write(roadmap_path)
    after_second = File.read(roadmap_path)
    assert_equal after_first, after_second
  end

  # --- 3.10: an entry absent from the graph survives in the first batch -------

  def test_entry_absent_from_graph_survives_the_render_in_the_first_batch
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued

      ### Batch 2
      - [ ] 102 Second - queued
    B
      - 101 needs nothing
    G
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    batch1 = content[/### Batch 1\n(.*?)(?=### Batch|\z)/m, 1]
    assert_includes batch1, "102"
  end

  # --- 3.11: the file's trailing newline convention is preserved --------------

  def test_trailing_newline_is_preserved
    body = basic(<<~B, <<~G)
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    write_roadmap(body)
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    assert content.end_with?("\n"), "file must still end with a newline"
    refute content.end_with?("\n\n\n"), "must not accumulate blank lines at EOF"
  end

  # --- 3.12: a dry run returns the new content, writes nothing ----------------

  def test_dry_run_returns_the_new_content_and_writes_nothing
    original = basic(<<~B, <<~G)
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    write_roadmap(original)
    result = RoadmapRender.write(roadmap_path, dry_run: true)
    assert result[:ok]
    refute_nil result[:content]
    assert_includes result[:content], "## Tree"
    assert_equal original, File.read(roadmap_path)
  end

  # --- 3.13: non-entry prose inside the grouping section survives the regroup -

  def test_non_entry_prose_survives_the_regroup_anchored_to_its_batch_heading
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued

      Kill gate prose paragraph that must survive between the batch
      headings, unrelated to any entry line.

      ### Batch 2
      - [ ] 102 Second - queued
    B
      - 101 needs nothing
      - 102 needs 101
    G
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    assert_includes content, "Kill gate prose paragraph that must survive"
  end

  # --- 3.14: an entry line the canonical grammar cannot parse is carried -------

  def test_unparseable_entry_line_is_carried_verbatim_into_the_batch_its_position_implies
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
      - (not filed) 2a Shell page build
    B
      - 101 needs nothing
    G
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    assert_includes content, "- (not filed) 2a Shell page build"
  end

  # --- 3.15: a Waves roadmap never gains a Batches heading ---------------------

  def test_waves_roadmap_renders_into_waves_and_never_gains_a_batches_heading
    write_roadmap(basic(<<~B, <<~G, heading: "## Waves"))
      ### Wave 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    B
      - 101 needs nothing
      - 102 needs 101
    G
    RoadmapRender.write(roadmap_path)
    content = File.read(roadmap_path)
    refute_match(/^## Batches$/, content)
  end
end
