# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/search"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class SearchTest < Plastic::TestCase
  def test_searches_loaded_sources_and_explicit_scope_replaces_them
    write_document("global", "global evidence")
    write_document("other", "other evidence")

    loaded = plastic("search", "evidence", "--json", env: { "PLASTIC_SOURCE_PROJECTS" => "global, other" }, table: Plastic::CLI::TABLE)
    explicit = plastic("search", "evidence", "--source-project", "other", "--json", env: { "PLASTIC_SOURCE_PROJECTS" => "global" }, table: Plastic::CLI::TABLE)

    assert_equal 0, loaded.code
    assert_includes loaded.out, "global"
    assert_includes loaded.out, "other"
    refute_includes explicit.out, "global"
    assert_includes explicit.out, "other"
  end

  def test_fuses_canonical_selected_sources_with_stable_rrf_order
    write_document("global", "global evidence", path: "z.md")
    write_document("other", "other evidence", path: "a.md")
    write_document("third", "third evidence", path: "m.md")

    result = plastic("search", "evidence", "--source-project", "third", "--source-project", " global ",
      "--source-project", "third", "--source-project", "other", "--json", table: Plastic::CLI::TABLE)
    document = JSON.parse(result.out)
    rows = document.fetch("result").fetch("results")

    assert_equal 0, result.code
    assert_equal %w[global other third], rows.map { |row| row.fetch("store") }
    assert_equal [1, 1, 1], rows.map { |row| row.fetch("local_rank") }
    assert_equal [1.0 / 61, 1.0 / 61, 1.0 / 61], rows.map { |row| row.fetch("rrf_score") }
  end

  def test_rejects_invalid_and_excessive_limits
    %w[0 101 word].each do |limit|
      result = plastic("search", "evidence", "--limit", limit, table: Plastic::CLI::TABLE)

      assert_equal 2, result.code
      assert_match(/limit/, result.err)
    end
  end

  def test_defaults_to_twenty_results_and_bounds_each_excerpt
    25.times { |index| write_document("global", "needle #{index}", path: "#{index}.md") }

    result = plastic("search", "needle", "--json", table: Plastic::CLI::TABLE)
    rows = JSON.parse(result.out).fetch("result").fetch("results")

    assert_equal 0, result.code
    assert_equal 20, rows.length
    assert rows.all? { |row| row.fetch("body").length <= 320 }
  end

  def test_blank_scope_falls_back_and_unknown_scope_fails
    write_document("global", "evidence")

    blank = plastic("search", "evidence", "--source-project", "   ", "--json", table: Plastic::CLI::TABLE)
    unknown = plastic("search", "evidence", "--source-project", "missing", table: Plastic::CLI::TABLE)

    assert_equal 0, blank.code
    assert_includes blank.out, "global"
    assert_equal 2, unknown.code
    assert_match(/unknown source projects: missing/, unknown.err)
  end

  def test_centers_an_accent_insensitive_fts_match
    write_document("global", ("prefix " * 100) + "café")
    result = plastic("search", "cafe", "--json", table: Plastic::CLI::TABLE)
    excerpt = JSON.parse(result.out).fetch("result").fetch("results").fetch(0).fetch("body")

    assert_equal 0, result.code
    assert_includes excerpt, "café"
  end

  def test_pins_a_hit_to_its_historical_revision_through_concurrent_replacement_and_removal
    graphs = Plastic::Graph.open(home: @plastic_home, store: "global")
    writer = Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin)
    writer.write("1", "evidence.md", "first evidence")
    graphs.retrieval.backfill!
    hit = sole(graphs.retrieval.search("evidence"))
    writer.write("1", "evidence.md", "second evidence")
    writer.remove("1", "evidence.md")

    document = graphs.retrieval.fetch_reference(graphs.retrieval.search_reference(hit))

    assert_equal "first evidence", document.fetch(:body)
    assert_equal hit.fetch("sha256"), document.fetch(:revision)
    assert_includes document.fetch(:uri), hit.fetch("sha256")
  end

  def test_centers_the_excerpt_on_nonadjacent_matching_evidence
    body = ("prefix " * 80) + "needle" + (" filler" * 8) + " evidence" + (" suffix" * 80)
    write_document("global", body)

    result = plastic("search", "needle evidence", "--json", table: Plastic::CLI::TABLE)
    assert_equal 0, result.code
    rows = JSON.parse(result.out).fetch("result").fetch("results")
    assert_equal 1, rows.length, result.out
    excerpt = rows.fetch(0).fetch("body")

    assert_includes excerpt, "needle"
    assert_includes excerpt, "evidence"
    refute_match(/\Aprefix/, excerpt)
  end

  def test_marks_archived_hits_and_leaves_every_selected_store_unchanged
    intent = open_intent("Archived", status: "future")
    write("#{intent.dir}/research.md", "archived evidence")
    assert_equal 0, plastic("intent", "archive", intent.intent_id, table: Plastic::CLI::TABLE).code
    before = selected_store_bytes

    result = plastic("search", "archived evidence", "--source-project", "global", "--json", table: Plastic::CLI::TABLE)
    hit = JSON.parse(result.out).fetch("result").fetch("results").fetch(0)

    assert_equal 0, result.code
    assert_equal true, hit.fetch("archived")
    assert_equal before, selected_store_bytes
  end

  private

  def write_document(store, body, path: "evidence.md")
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write("1", path, body)
    graphs.retrieval.backfill!
  end

  def selected_store_bytes
    %w[work_graph.db knowledge_graph.db references.db].to_h do |name|
      path = store_path(name)
      [name, File.binread(path)]
    end
  end
end
