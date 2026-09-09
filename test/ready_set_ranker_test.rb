# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/ready_set"

# ReadySet's ranker seam (intent 336, n4): FinishFirstRanker (default),
# CriticalPathRanker, and C16's routing rule enforced mechanically - a
# ranker row is a frozen hash over a fixed key list of state- and
# edge-derived fields, and the module's own source never names the
# cross-intent knowledge-graph field.
class ReadySetRankerTest < Minitest::Test
  def row(id:, kind: "work", batch: 1, retry_flag: false, downstream_hops: 1, on_critical_path: false)
    ReadySet.build_row(id: id, kind: kind, batch: batch, retry_flag: retry_flag,
                        downstream_hops: downstream_hops, on_critical_path: on_critical_path)
  end

  def test_finish_first_is_the_default_ranker
    dir = Dir.mktmpdir("ready-set-ranker")
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "graph.md"), <<~MD)
      # Graph

      ## Graph
      - n1 needs nothing

      ## Status
    MD
    File.write(File.join(dir, "nodes", "n1.md"), <<~MD)
      ---
      node: n1
      kind: work
      files: []
      budget: 1000
      ---
      # n1

      ## Steps
      1. go

      ## Proven by
      (later)
    MD
    result = ReadySet.analyze(dir)
    assert_equal "finish-first", result[:ranker_name]
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_finish_first_puts_a_retry_before_a_fresh_node
    rows = [row(id: "fresh", retry_flag: false, batch: 1), row(id: "retry", retry_flag: true, batch: 1)]
    ranked = ReadySet::FinishFirstRanker.new.rank(rows)
    assert_equal "retry", ranked.first[:id]
  end

  def test_finish_first_prefers_the_deeper_batch
    rows = [row(id: "shallow", batch: 1), row(id: "deep", batch: 3)]
    ranked = ReadySet::FinishFirstRanker.new.rank(rows)
    assert_equal "deep", ranked.first[:id]
  end

  def test_finish_first_tie_breaks_on_id
    rows = [row(id: "b", batch: 1), row(id: "a", batch: 1)]
    ranked = ReadySet::FinishFirstRanker.new.rank(rows)
    assert_equal %w[a b], ranked.map { |r| r[:id] }
  end

  def test_critical_path_ranker_puts_the_path_first
    rows = [row(id: "off", on_critical_path: false, downstream_hops: 5),
            row(id: "on", on_critical_path: true, downstream_hops: 1)]
    ranked = ReadySet::CriticalPathRanker.new.rank(rows)
    assert_equal "on", ranked.first[:id]
  end

  def test_critical_path_ranker_orders_the_rest_by_downstream_hops
    rows = [row(id: "short", on_critical_path: false, downstream_hops: 1),
            row(id: "long", on_critical_path: false, downstream_hops: 4)]
    ranked = ReadySet::CriticalPathRanker.new.rank(rows)
    assert_equal %w[long short], ranked.map { |r| r[:id] }
  end

  def test_swapping_the_ranker_changes_only_the_ready_order
    dir = build_two_node_ready_fixture
    finish_first = ReadySet.analyze(dir, ranker: ReadySet::FinishFirstRanker.new)
    critical_path = ReadySet.analyze(dir, ranker: ReadySet::CriticalPathRanker.new)

    assert_equal finish_first[:batches], critical_path[:batches]
    assert_equal finish_first[:nodes].transform_values { |v| v[:blockers] },
                 critical_path[:nodes].transform_values { |v| v[:blockers] }
    assert_equal finish_first[:ranked_ready].map { |r| r[:id] }.sort,
                 critical_path[:ranked_ready].map { |r| r[:id] }.sort
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_each_ranker_reports_its_name
    assert_equal "finish-first", ReadySet::FinishFirstRanker.new.name
    assert_equal "critical-path", ReadySet::CriticalPathRanker.new.name
  end

  def test_ranker_rows_carry_no_telemetry_key
    forbidden = %i[tokens wall model suite packet]
    assert_empty(ReadySet::ROW_KEYS & forbidden)
  end

  # C16 (finding 3): ROW_KEYS is not decoration - build_row's actual keys,
  # and the keys of a row taken from analyze's own ranked_ready, must equal
  # it exactly. Adding a stray key to build_row (a telemetry field, say)
  # must turn this red.
  def test_build_row_keys_equal_row_keys_exactly
    assert_equal ReadySet::ROW_KEYS, row(id: "n1").keys
  end

  def test_ranked_ready_rows_carry_exactly_row_keys
    dir = build_two_node_ready_fixture
    result = ReadySet.analyze(dir)
    refute_empty result[:ranked_ready]
    result[:ranked_ready].each { |r| assert_equal ReadySet::ROW_KEYS, r.keys }
  ensure
    FileUtils.rm_rf(dir)
  end

  # Finding 4: analyze must apply the injected ranker's order to
  # ranked_ready, not the pre-rank rows. A reversing ranker over a ready set
  # whose default (finish-first) order is not already its own reverse
  # proves the wiring; changing `ranked_ready: ranked` to `ranked_ready: rows`
  # in ReadySet.analyze would make this fail.
  def test_analyze_applies_the_injected_ranker_to_ranked_ready
    dir = build_two_node_ready_fixture
    default_order = ReadySet.analyze(dir)[:ranked_ready].map { |r| r[:id] }
    refute_equal default_order, default_order.reverse, "the fixture must have a non-palindromic order"

    reversing = Class.new do
      def rank(rows)
        rows.reverse
      end

      def name
        "reverse-order"
      end
    end.new
    reversed_order = ReadySet.analyze(dir, ranker: reversing)[:ranked_ready].map { |r| r[:id] }
    assert_equal default_order.reverse, reversed_order
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_ready_set_source_never_names_sources
    source = File.read(File.expand_path("../scripts/lib/ready_set.rb", __dir__))
    refute_match(/sources/, source)
  end

  def test_ranker_rows_are_frozen
    r = row(id: "n1")
    assert r.frozen?
    assert_raises(FrozenError) { r[:id] = "changed" }
  end

  def test_ranking_an_empty_set_returns_empty
    assert_equal [], ReadySet::FinishFirstRanker.new.rank([])
    assert_equal [], ReadySet::CriticalPathRanker.new.rank([])
  end

  def test_any_object_answering_rank_and_name_is_accepted
    dir = build_two_node_ready_fixture
    custom = Class.new do
      def rank(rows)
        rows.reverse
      end

      def name
        "custom"
      end
    end.new
    result = ReadySet.analyze(dir, ranker: custom)
    assert_equal "custom", result[:ranker_name]
  ensure
    FileUtils.rm_rf(dir)
  end

  private

  def build_two_node_ready_fixture
    dir = Dir.mktmpdir("ready-set-ranker")
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "graph.md"), <<~MD)
      # Graph

      ## Graph
      - n1 needs nothing
      - n2 needs nothing

      ## Status
    MD
    %w[n1 n2].each do |id|
      File.write(File.join(dir, "nodes", "#{id}.md"), <<~MD)
        ---
        node: #{id}
        kind: work
        files: []
        budget: 1000
        ---
        # #{id}

        ## Steps
        1. go

        ## Proven by
        (later)
      MD
    end
    dir
  end
end
