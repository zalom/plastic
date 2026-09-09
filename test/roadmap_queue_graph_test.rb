# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../scripts/lib/roadmap_queue"

# RoadmapQueue's frontier from a roadmap's own ## Graph section (intent 336,
# n6): a roadmap carrying an exact ## Graph heading dispatches by edges, with
# a delivered entry counting as done and INDEX still winning every conflict.
# A roadmap with no exact ## Graph heading, or one whose graph section yields
# no edges, keeps today's first-wave-with-a-queued-entry behavior byte for
# byte. Hermetic: every fixture lives in a Dir.mktmpdir; this file never
# reads the real ~/.plastic.
class RoadmapQueueGraphTest < Minitest::Test
  NOW = Time.utc(2026, 9, 9, 12, 0, 0)

  def setup
    @home = Dir.mktmpdir("roadmap-queue-graph")
    @roadmaps = File.join(@home, "roadmaps")
    FileUtils.mkdir_p(@roadmaps)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_roadmap(slug, body)
    File.write(File.join(@roadmaps, "#{slug}.md"), body)
  end

  # waves: {"Heading" => ["id text — status", ...], ...}
  def write_graph_roadmap(waves:, graph:, slug: "demo", graph_heading: "## Graph")
    lines = ["# Roadmap: Demo", "", "## Goal", "Ship it.", "", "## Batches"]
    waves.each do |heading, entries|
      lines << "### #{heading}"
      entries.each { |e| lines << "- [ ] #{e}" }
    end
    lines << ""
    lines << graph_heading
    lines << graph
    write_roadmap(slug, lines.join("\n") + "\n")
  end

  def write_index(active: [], future: [], completed: [], abandoned: [])
    index_line = ->(id) { "- [#{id} — Title](store/#{id}--slug/#{id}--slug.md) — 2026-09-09 note." }
    lines = ["# Index", "", "## Active", ""]
    active.each { |id| lines << index_line.call(id) }
    lines += ["", "## Future", ""]
    future.each { |id| lines << index_line.call(id) }
    lines += ["", "## Clusters", "", "## Abandoned", ""]
    abandoned.each { |id| lines << index_line.call(id) }
    lines += ["", "## Completed", ""]
    completed.each { |id| lines << index_line.call(id) }
    File.write(File.join(@home, "INDEX.md"), lines.join("\n") + "\n")
  end

  def reader(ranker: FileOrderRanker.new)
    RoadmapQueue.new(roadmaps_dir: @roadmaps, now: NOW, ranker: ranker)
  end

  def test_graph_roadmap_dispatches_by_edges
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First — queued", "102 Second — queued", "103 Third — queued"] },
      graph: "- 101 needs nothing\n- 102 needs nothing\n- 103 needs 101 102\n"
    )
    result = reader.queue
    ids = result["dispatchable_queue"].map { |e| e["id"] }
    assert_equal %w[101 102], ids.sort
  end

  def test_a_graph_heading_with_a_trailing_parenthetical_is_not_a_graph_section
    body = <<~MD
      # Roadmap: Demo

      ## Batches

      ### Batch 1
      - [ ] 101 First — queued

      ## Graph (2026-09-01, superseded by the Nodes and Edges under ## Batches on 2026-09-04)
      - 101 needs 999
    MD
    write_roadmap("demo", body)
    result = reader.queue
    assert_equal ["101"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  def test_a_graph_section_with_no_edges_falls_back_to_batches
    body = <<~MD
      # Roadmap: Demo

      ## Batches

      ### Batch 1
      - [ ] 101 First — queued

      ## Graph
      Prose only, no real edge lines here.
    MD
    write_roadmap("demo", body)
    result = reader.queue
    assert_equal ["101"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  # A hermetic reproduction of the real hazard R-C5 names (never a live read
  # of ~/.plastic): claudechat/roadmaps/chat-shell-maturity.md:8 carries this
  # exact heading text. A prefix match would read it as an empty graph and
  # silently report exhausted; the fix falls all the way back to the wave
  # behavior, byte for byte with the pre-336 payload shape.
  def test_live_roadmap_fixtures_produce_the_pre_change_payload
    body = <<~MD
      # Roadmap: Chat shell maturity fixture

      ## Batches

      ### Batch 1
      - [ ] 201 Ship the shell — queued

      ## Graph (2026-09-01, superseded by the Nodes and Edges under ## Batches on 2026-09-04)
      - 201 needs 555
    MD
    write_roadmap("chat-shell-maturity", body)
    result = reader.queue
    assert_equal "dispatchable", result["state"]
    assert_equal ["201"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  def test_roadmap_without_a_graph_keeps_wave_behavior
    body = <<~MD
      # Roadmap: Demo

      ## Batches

      ### Batch 1
      - [ ] 101 First — queued
      - [ ] 102 Second — queued
    MD
    write_roadmap("demo", body)
    result = reader.queue
    assert_equal %w[101 102], result["dispatchable_queue"].map { |e| e["id"] }.sort
  end

  def test_delivered_entry_satisfies_a_needs_edge
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First — delivered", "102 Second — queued"] },
      graph: "- 101 needs nothing\n- 102 needs 101\n"
    )
    result = reader.queue
    assert_equal ["102"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  def test_index_still_wins_over_the_roadmap_token
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First — queued", "102 Second — queued"] },
      graph: "- 101 needs nothing\n- 102 needs 101\n"
    )
    write_index(completed: ["101"])
    result = reader.queue
    assert_equal ["102"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  def test_json_contract_keys_are_unchanged
    expected_keys = %w[generated_for mode scope state roadmap frontier_wave dispatchable_queue
                        in_flight blocked tie tie_candidates ranking_strategy generated_at]
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First — queued"] },
      graph: "- 101 needs nothing\n"
    )
    assert_equal expected_keys.sort, reader.queue.keys.sort
  end

  def test_frontier_wave_names_the_batch_holding_the_first_dispatchable_entry
    write_graph_roadmap(
      waves: { "Alpha" => ["101 First — queued"], "Beta" => ["102 Second — queued"] },
      graph: "- 101 needs nothing\n- 102 needs 101\n"
    )
    result = reader.queue
    assert_equal "Alpha", result["frontier_wave"]
  end

  def test_cyclic_roadmap_graph_reports_an_error
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First — queued", "102 Second — queued"] },
      graph: "- 101 needs 102\n- 102 needs 101\n"
    )
    result = reader.queue
    assert_equal "error", result["state"]
    assert_match(/cyc/, result["frontier_wave"].to_s)
  end

  def test_graph_id_absent_from_batches_is_reported_not_dispatched
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First — queued"] },
      graph: "- 101 needs 999\n- 999 needs nothing\n"
    )
    result = reader.queue
    assert_empty result["dispatchable_queue"]
    refute_equal "error", result["state"]
  end

  def test_a_fenced_example_edge_is_not_an_edge
    body = <<~MD
      # Roadmap: Demo

      ## Batches

      ### Batch 1
      - [ ] 101 First — queued

      ## Graph
      - 101 needs nothing

      Example only, not a real edge:
      ```
      - 101 needs 999
      ```
    MD
    write_roadmap("demo", body)
    result = reader.queue
    assert_equal ["101"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  def test_ranker_injection_still_works
    write_graph_roadmap(
      waves: { "Batch 1" => ["102 Second — queued", "101 First — queued"] },
      graph: "- 101 needs nothing\n- 102 needs nothing\n"
    )
    reversed = Class.new do
      def rank(rows)
        rows.sort_by { |r| r[:id] }.reverse
      end

      def name
        "reverse-order"
      end
    end.new
    result = reader(ranker: reversed).queue
    assert_equal %w[102 101], result["dispatchable_queue"].map { |e| e["id"] }
    assert_equal "reverse-order", result["ranking_strategy"]
  end
end
