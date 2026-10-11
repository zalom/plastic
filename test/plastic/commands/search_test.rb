# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/search"
require_relative "../../../scripts/lib/plastic/graph/retrieval/evidence/writer"
require_relative "old_store"

module SearchTestSupport
  private

  def write_document(store, body, path: "evidence.md")
    graphs = Plastic::Graph.create(home: @plastic_home, store:)
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin).write("1", path, body)
    graphs.retrieval.backfill
    graphs.retrieval.archived?("1")
  end

  def selected_store_bytes
    %w[work_graph.db knowledge_graph.db references.db].to_h do |name|
      path = store_path(name)
      [name, File.binread(path)]
    end
  end
end

module SearchTestAssertionSupport
  private

  def assert_scoped_results(loaded, explicit)
    assert_equal 0, loaded.code
    assert_includes loaded.out, "global"
    assert_includes loaded.out, "other"
    refute_includes explicit.out, "global"
    assert_includes explicit.out, "other"
  end

  def assert_fused_rows(result)
    assert_equal 0, result.code
    assert_fused_stores(result)
    assert_fused_ranks(result)
    assert_fused_scores(result)
  end

  def fused_rows(result) = JSON.parse(result.out).fetch("result").fetch("rows")

  def search_rows(query)
    result = plastic("search", query, "--json", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [result.code, result.err]
    fused_rows(result)
  end

  def assert_fused_stores(result) = assert_equal(%w[global other third], fused_rows(result).map { |row| row.fetch("store") })

  def assert_fused_ranks(result) = assert_equal([1, 2, 3], fused_rows(result).map { |row| row.fetch("rank") })

  def assert_fused_scores(result) = assert(fused_rows(result).none? { |row| row.key?("score") || row.key?("rrf_score") || row.key?("body") })

  def assert_scope_result(blank, unknown)
    assert_equal 0, blank.code
    assert_includes blank.out, "global"
    assert_equal 2, unknown.code
    assert_match(/unknown source projects: missing/, unknown.err)
  end

  def assert_maintenance_result(result, root, knowledge, references)
    assert_equal 1, result.code
    assert_match(/maintenance/, result.out)
    refute_path_exists File.join(root, "work_graph.db")
    assert_equal knowledge, File.binread(File.join(root, "knowledge_graph.db"))
    assert_equal references, File.binread(File.join(root, "references.db"))
  end

  def assert_pinned_document(hit, document)
    assert_equal "first evidence", document.fetch(:body)
    assert_equal hit.fetch("sha256"), document.fetch(:revision)
    assert_includes document.fetch(:uri), hit.fetch("sha256")
  end

  def assert_centered_excerpt(result)
    assert_equal 0, result.code
    excerpt = JSON.parse(result.out).fetch("result").fetch("rows").fetch(0).fetch("passage")

    assert_includes excerpt, "needle"
    assert_includes excerpt, "evidence"
    refute_match(/\Aprefix/, excerpt)
  end

  def assert_archived_result(result, before)
    hit = JSON.parse(result.out).fetch("result").fetch("rows").fetch(0)

    assert_equal [0, ""], [result.code, result.err]
    assert hit.fetch("archived")
    assert_equal before, selected_store_bytes
  end

  def historical_document
    graphs = Plastic::Graph.open(home: @plastic_home, store: "global")
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin)
    writer.write("1", "evidence.md", "first evidence")
    graphs.retrieval.backfill
    hit = sole(graphs.retrieval.search("evidence"))
    replace_and_remove(writer)

    [hit, graphs.retrieval.fetch_reference(graphs.retrieval.search_reference(hit))]
  end

  def replace_and_remove(writer)
    writer.write("1", "evidence.md", "second evidence")
    writer.remove("1", "evidence.md")
  end
end

class SearchScopeTest < Plastic::TestCase
  include SearchTestSupport
  include SearchTestAssertionSupport

  def test_searches_loaded_sources_and_explicit_scope_replaces_them
    write_document("global", "global evidence")
    write_document("other", "other evidence")

    loaded = plastic("search", "evidence", "--json", env: { "PLASTIC_SOURCE_PROJECTS" => "global, other" }, table: Plastic::CLI::TABLE)
    explicit = plastic("search", "evidence", "--source-project", "other", "--json", env: { "PLASTIC_SOURCE_PROJECTS" => "global" }, table: Plastic::CLI::TABLE)

    assert_scoped_results(loaded, explicit)
  end

  def test_fuses_canonical_selected_sources_with_stable_rrf_order
    write_document("global", "global evidence", path: "z.md")
    write_document("other", "other evidence", path: "a.md")
    write_document("third", "third evidence", path: "m.md")

    result = plastic("search", "evidence", "--source-project", "third", "--source-project", " global ",
      "--source-project", "third", "--source-project", "other", "--json", table: Plastic::CLI::TABLE)

    assert_fused_rows(result)
  end

  def test_a_hit_prints_its_rank_passage_and_uri_first
    write_document("global", "global evidence")

    hit = search_rows("evidence").fetch(0)

    assert_equal %w[rank passage uri], hit.keys.first(3)
    assert_equal [1, "global evidence"], hit.values_at("rank", "passage")
    assert_match(%r{\Aplastic://global/1/evidence\.md\?revision=}, hit.fetch("uri"))
  end

  def test_a_hit_prints_no_body_and_no_score
    write_document("global", "global evidence")

    assert(search_rows("evidence").fetch(0).keys.none? { |key| %w[body score rrf_score local_rank sha256].include?(key) })
  end

  def test_plain_output_prints_readable_lines
    write_document("global", "global evidence")

    result = plastic("search", "evidence", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [result.code, result.err]
    refute_match(/\{|=>|\[/, result.out)
  end

  def test_rejects_invalid_and_excessive_limits
    %w[0 101 word].each do |limit|
      result = plastic("search", "evidence", "--limit", limit, table: Plastic::CLI::TABLE)

      assert_equal 2, result.code
      assert_equal "", result.out
      assert_match(/limit/, result.err)
    end
  end

  def test_defaults_to_twenty_results_and_bounds_each_excerpt
    25.times { |index| write_document("global", "needle #{index}", path: "#{index}.md") }

    rows = search_rows("needle")

    assert_equal 20, rows.length
    assert(rows.all? { |row| row.fetch("passage").length <= 320 })
  end

  def test_blank_scope_falls_back_and_unknown_scope_fails
    write_document("global", "evidence")

    blank = plastic("search", "evidence", "--source-project", "   ", "--json", table: Plastic::CLI::TABLE)
    unknown = plastic("search", "evidence", "--source-project", "missing", table: Plastic::CLI::TABLE)

    assert_scope_result(blank, unknown)
  end

  def test_centers_an_accent_insensitive_fts_match
    write_document("global", ("prefix " * 100) + "café")
    result = plastic("search", "cafe", "--json", table: Plastic::CLI::TABLE)
    excerpt = JSON.parse(result.out).fetch("result").fetch("rows").fetch(0).fetch("passage")

    assert_equal 0, result.code
    assert_includes excerpt, "café"
    assert_equal "", result.err
  end

  def test_keeps_an_accent_insensitive_match_after_combining_mark_fillers
    body = ("é " * 180) + "café"
    write_document("global", body)

    excerpt = search_rows("cafe").fetch(0).fetch("passage")

    assert_operator excerpt.length, :<=, 320
    assert_includes excerpt, "café"
  end

  def test_reports_maintenance_without_recreating_a_missing_selected_store_database
    write_document("other", "other evidence")
    root = File.join(@plastic_home, "stores", "other")
    Plastic::Graph.create(home: @plastic_home, store: "other").retrieval.archived?("1")
    knowledge = File.binread(File.join(root, "knowledge_graph.db"))
    references = File.binread(File.join(root, "references.db"))
    File.delete(File.join(root, "work_graph.db"))

    result = plastic("search", "evidence", "--source-project", "other", "--json", table: Plastic::CLI::TABLE)

    assert_maintenance_result(result, root, knowledge, references)
  end
end

class SearchEvidenceTest < Plastic::TestCase
  include SearchTestSupport
  include SearchTestAssertionSupport

  def test_pins_a_hit_to_its_historical_revision_through_concurrent_replacement_and_removal
    hit, document = historical_document

    assert_pinned_document(hit, document)
  end

  def test_centers_the_excerpt_on_nonadjacent_matching_evidence
    body = ("prefix " * 80) + "needle" + (" filler" * 8) + " evidence" + (" suffix" * 80)
    write_document("global", body)

    result = plastic("search", "needle evidence", "--json", table: Plastic::CLI::TABLE)

    assert_centered_excerpt(result)
  end

  def test_marks_archived_hits_and_leaves_every_selected_store_unchanged
    intent = open_intent("Archived", status: "future")
    write("#{intent.dir}/research.md", "archived evidence")

    assert_equal 0, plastic("intent", "archive", intent.intent_id, table: Plastic::CLI::TABLE).code
    before = selected_store_bytes

    result = plastic("search", "archived evidence", "--source-project", "global", "--json", table: Plastic::CLI::TABLE)

    assert_archived_result(result, before)
  end
end

class SearchRepairTest < Plastic::TestCase
  include OldStore

  def search = plastic("search", "evidence", "--source-project", OLD, table: Plastic::CLI::TABLE)

  def test_a_search_on_a_store_with_no_backfill_marker_names_its_repair
    old_store
    result = search

    assert_equal 1, result.code
    assert_includes result.out + result.err, "run plastic project new old #{checkout}"
  end

  def test_after_project_new_a_search_reads_a_store_made_before_the_marker
    old_store
    repair
    result = search

    assert_equal [0, true], [result.code, result.out.include?("plastic://old/1/notes.md")]
  end
end
