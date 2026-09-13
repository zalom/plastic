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

  # waves: {"Heading" => ["id text - status", ...], ...}
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
    index_line = ->(id) { "- [#{id} - Title](store/#{id}--slug/#{id}--slug.md) - 2026-09-09 note." }
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
      waves: { "Batch 1" => ["101 First - queued", "102 Second - queued", "103 Third - queued"] },
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
      - [ ] 101 First - queued

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
      - [ ] 101 First - queued

      ## Graph
      Prose only, no real edge lines here.
    MD
    write_roadmap("demo", body)
    result = reader.queue
    assert_equal ["101"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  # [R-C5] Runs the queue over COPIES of every *.md under the two live
  # roadmaps/ directories (never a live read that could write to the real
  # store): for a file with no real ## Graph section, the graph path must be
  # a no-op, byte for byte with the pre-336 wave-only fallback. A file that
  # genuinely carries a real ## Graph section (327's own roadmap dogfoods
  # this branch's own feature) is checked differently: every id its
  # frontier names must be a real graph or batch id, never invented. Skips
  # cleanly when no live roadmaps/ directory exists, so the suite stays
  # green on a fresh machine.
  def live_roadmap_files
    dirs = (Dir.glob(File.expand_path("~/.plastic/projects/*/roadmaps")) +
            Dir.glob(File.expand_path("~/.plastic/roadmaps"))).select { |d| Dir.exist?(d) }
    dirs.flat_map { |d| Dir.glob(File.join(d, "*.md")) }.reject { |p| p.end_with?(".savepoint.md") }
  end

  def test_live_roadmap_fixtures_take_the_no_op_path_unless_they_have_a_real_graph
    live_files = live_roadmap_files
    skip("no live roadmap files found under ~/.plastic/projects/*/roadmaps or ~/.plastic/roadmaps") if live_files.empty?

    live_files.each do |source_path|
      copy_dir = Dir.mktmpdir("roadmap-queue-live-copy")
      begin
        copy_path = File.join(copy_dir, File.basename(source_path))
        FileUtils.cp(source_path, copy_path)
        queue = RoadmapQueue.new(roadmaps_dir: copy_dir, now: NOW)

        result = queue.roadmap(copy_path)
        parsed = queue.send(:reconcile, [queue.send(:parse_roadmap, copy_path)]).first

        if parsed[:graph_edges].nil?
          fallback = queue.send(:wave_frontier_for, parsed)
          if fallback.nil?
            assert_nil result[:frontier],
                       "#{source_path}: the graph path must be a no-op when there is no real graph"
          else
            assert_equal fallback, result[:frontier],
                         "#{source_path}: the graph path must be a no-op when there is no real graph"
          end
        else
          known_ids = queue.send(:all_graph_nodes, parsed[:graph_edges][:edges]) +
                      parsed[:waves].flat_map { |w| w[:entries].map { |e| e[:id] } }
          entries = result[:frontier] ? result[:frontier][:dispatchable] + result[:frontier][:in_flight] : []
          entries.each { |e| assert_includes known_ids, e["id"], "#{source_path}: #{e['id']} is not a real id" }
        end
      ensure
        FileUtils.remove_entry(copy_dir)
      end
    end
  end

  def test_roadmap_without_a_graph_keeps_wave_behavior
    body = <<~MD
      # Roadmap: Demo

      ## Batches

      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    MD
    write_roadmap("demo", body)
    result = reader.queue
    assert_equal %w[101 102], result["dispatchable_queue"].map { |e| e["id"] }.sort
  end

  def test_delivered_entry_satisfies_a_needs_edge
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - delivered", "102 Second - queued"] },
      graph: "- 101 needs nothing\n- 102 needs 101\n"
    )
    result = reader.queue
    assert_equal ["102"], result["dispatchable_queue"].map { |e| e["id"] }
  end

  def test_index_still_wins_over_the_roadmap_token
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - queued", "102 Second - queued"] },
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
      waves: { "Batch 1" => ["101 First - queued"] },
      graph: "- 101 needs nothing\n"
    )
    assert_equal expected_keys.sort, reader.queue.keys.sort
  end

  def test_frontier_wave_names_the_batch_holding_the_first_dispatchable_entry
    write_graph_roadmap(
      waves: { "Alpha" => ["101 First - queued"], "Beta" => ["102 Second - queued"] },
      graph: "- 101 needs nothing\n- 102 needs 101\n"
    )
    result = reader.queue
    assert_equal "Alpha", result["frontier_wave"]
  end

  def test_cyclic_roadmap_graph_reports_an_error
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - queued", "102 Second - queued"] },
      graph: "- 101 needs 102\n- 102 needs 101\n"
    )
    result = reader.queue
    assert_equal "error", result["state"]
    assert_match(/cyc/, result["frontier_wave"].to_s)
  end

  def test_graph_id_absent_from_batches_is_reported_not_dispatched
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - queued"] },
      graph: "- 101 needs 999\n- 999 needs nothing\n"
    )
    result = reader.queue
    assert_empty result["dispatchable_queue"]
    refute_equal "error", result["state"]
    reasons = result["blocked"].map { |e| e["reason"] }
    assert_includes reasons, "graph names \"999\", no batch entry"
  end

  # R-2, the G4 partial-migration path: a batch entry the graph does not
  # name is never dropped. It keeps the pre-change wave behavior (needing
  # nothing, so it stays dispatchable) rather than silently vanishing the
  # moment the roadmap grows a ## Graph section.
  def test_a_batch_entry_the_graph_does_not_name_stays_dispatchable
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - delivered", "102 Second - queued"] },
      graph: "- 101 needs nothing\n"
    )
    result = reader.queue
    assert_equal ["102"], result["dispatchable_queue"].map { |e| e["id"] }
    refute_equal "exhausted", result["state"]
  end

  # The invariant guard (R-2's third rule): state is never "exhausted" while
  # a queued entry sits unaccounted for. Here 101 can never resolve (its
  # need 999 is not a real batch entry), so it stays queued forever - but it
  # must show up in `blocked` right alongside the unreported id, never
  # silently dropped the way an "exhausted" roadmap with no explanation
  # would read to auto mode.
  def test_a_queued_entry_stuck_behind_an_unreported_id_is_reported_too
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - queued"] },
      graph: "- 101 needs 999\n- 999 needs nothing\n"
    )
    result = reader.queue
    blocked_ids = result["blocked"].map { |e| e["id"] }
    assert_includes blocked_ids, "999"
    assert_includes blocked_ids, "101"
  end

  def test_a_fenced_example_edge_is_not_an_edge
    body = <<~MD
      # Roadmap: Demo

      ## Batches

      ### Batch 1
      - [ ] 101 First - queued

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
      waves: { "Batch 1" => ["102 Second - queued", "101 First - queued"] },
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

  # --- intent 337, n9: RoadmapQueue reads the shared model ------------------

  # 9.1: no second topological sort survives in roadmap_queue.rb - the one
  # sort is ReadySet.batches (327 D1).
  def test_roadmap_queue_defines_no_topological_sort_of_its_own
    source = File.read(File.expand_path("../scripts/lib/roadmap_queue.rb", __dir__))
    refute_match(/def topological_layers/, source)
  end

  # 9.2: no second "## Graph" reader survives - edges come from the shared
  # RoadmapGraph.parse_graph_section, which itself defers to GraphEdges.
  def test_roadmap_queue_parses_no_graph_section_of_its_own
    source = File.read(File.expand_path("../scripts/lib/roadmap_queue.rb", __dir__))
    refute_match(/def parse_roadmap_graph/, source)
  end

  # 9.3: the queue/which/roadmap payload contract is unchanged for a
  # multi-batch, multi-entry acyclic graph roadmap.
  def test_payload_is_unchanged_for_every_live_roadmap_fixture
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - delivered", "102 Second - queued"],
               "Batch 2" => ["103 Third - queued"] },
      graph: "- 101 needs nothing\n- 102 needs nothing\n- 103 needs 101 102\n"
    )
    result = reader.queue
    assert_equal ["102"], result["dispatchable_queue"].map { |e| e["id"] }
    assert_equal "dispatchable", result["state"]
    assert_equal "Batch 1", result["frontier_wave"]
  end

  # 9.4: a graphless roadmap keeps the wave-order frontier fallback.
  def test_graphless_roadmap_keeps_wave_order_frontier
    body = <<~MD
      # Roadmap: Demo

      ## Batches

      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    MD
    write_roadmap("demo", body)
    result = reader.queue
    assert_equal %w[101 102], result["dispatchable_queue"].map { |e| e["id"] }.sort
    assert_equal "Batch 1", result["frontier_wave"]
  end

  # 9.5: an id the graph names that no batch lists is still reported, not
  # swallowed, after the refactor.
  def test_unlisted_graph_id_is_still_reported_in_blocked
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - queued"] },
      graph: "- 101 needs 555\n- 555 needs nothing\n"
    )
    result = reader.queue
    reasons = result["blocked"].map { |e| e["reason"] }
    assert_includes reasons, "graph names \"555\", no batch entry"
  end

  # 9.6: a cyclic roadmap still returns the error state naming the whole path.
  def test_cyclic_roadmap_still_returns_error_state_with_the_whole_path
    write_graph_roadmap(
      waves: { "Batch 1" => ["101 First - queued", "102 Second - queued", "103 Third - queued"] },
      graph: "- 101 needs 102\n- 102 needs 103\n- 103 needs 101\n"
    )
    result = reader.queue
    assert_equal "error", result["state"]
    assert_match(/101.*>.*102.*>.*103.*>.*101/, result["frontier_wave"].to_s)
  end

  # 9.7: the injected ranker seam still orders a graph-driven dispatchable
  # queue, not only the wave-order fallback.
  def test_injected_ranker_still_orders_the_dispatchable_queue
    write_graph_roadmap(
      waves: { "Batch 1" => ["102 Second - queued", "101 First - queued"] },
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
  end

  # 9.8: entries within a batch keep the roadmap file's own order (not a
  # lexical sort) before the ranker ever sees them - resolved at the
  # 2026-09-10 plan review: chat-shell-maturity.md's rank 1 flips from "5"
  # to "2" under a lexical sort of one batch's entries.
  def test_dispatchable_order_matches_roadmap_file_order_within_a_batch
    write_graph_roadmap(
      waves: { "Batch 1" => ["205 Fifth - queued", "102 Second - queued", "101 First - queued"] },
      graph: "- 205 needs nothing\n- 102 needs nothing\n- 101 needs nothing\n"
    )
    result = reader.queue
    assert_equal %w[205 102 101], result["dispatchable_queue"].map { |e| e["id"] }
  end
end
