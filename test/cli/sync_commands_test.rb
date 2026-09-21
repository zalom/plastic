# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"
require_relative "../../scripts/lib/store_sync"
require_relative "../../scripts/doctor"

class CliSyncCommandsTest < Minitest::Test
  SPEC = "store/1--alpha/spec.md"
  PNG = "store/1--alpha/resources/shot.png"
  BYTES = "\x89PNG\x00\x01\xFE binary".b

  def setup
    @dir = Dir.mktmpdir("plastic-cli-sync")
    @fixture = CliFixture.new(@dir).global_store(active: [["1", "Alpha"]]).project("acme", active: [["2", "Beta"]])
    seed(SPEC, "# Spec\n\nThe heron nests by the river.\n")
    seed("store/1--alpha/savepoint.md", "2026-09-21T10:00:00Z  What  intent created\n2026-09-21T11:00:00Z  How  plan written\n")
    seed(PNG, BYTES)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def home
    @fixture.plastic_home
  end

  def seed(relative, body)
    path = File.join(home, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, body)
  end

  def plastic(*argv)
    [@fixture.out, @fixture.err].each do |io|
      io.truncate(0)
      io.rewind
    end
    Plastic::CLI.call(argv, directory: @dir, **@fixture.streams)
  end

  def sql(database, statement)
    Plastic::Sqlite.call(File.join(home, database), statement)
  end

  def row_body(path)
    sql("knowledge_graph.db", "SELECT CAST(sqlar_uncompress(data, sz) AS TEXT) AS body FROM doc WHERE path = '#{path}'").first["body"]
  end

  def change_row(path, text)
    sql("knowledge_graph.db", "UPDATE doc SET sz = length(CAST('#{text}' AS BLOB)), data = sqlar_compress(CAST('#{text}' AS BLOB)) WHERE path = '#{path}'")
  end

  def test_the_first_sync_builds_the_three_databases
    assert_equal 0, plastic("sync")

    %w[knowledge_graph.db work_graph.db references.db].each { |name| assert_path_exists File.join(home, name) }
  end

  def test_a_changed_file_is_read_into_its_row
    plastic("sync")
    seed(SPEC, "# Spec\n\nThe heron moved to the pond.\n")
    plastic("sync")

    assert_match(/^read\s+#{Regexp.escape(SPEC)}$/, @fixture.printed)
    assert_includes row_body(SPEC), "pond"
  end

  def test_a_changed_file_is_found_by_search_after_the_sync
    plastic("sync")
    seed(SPEC, "# Spec\n\nThe heron moved to the pond.\n")
    plastic("sync")
    plastic("search", "pond")

    assert_includes @fixture.printed, SPEC
  end

  def test_a_new_file_is_read_into_a_new_row
    plastic("sync")
    seed("store/1--alpha/plan-b.md", "A second plan.\n")
    plastic("sync")

    assert_includes row_body("store/1--alpha/plan-b.md"), "second plan"
  end

  def test_a_changed_row_is_written_out_to_its_file
    plastic("sync")
    change_row(SPEC, "row text")
    plastic("sync")

    assert_match(/^write\s+#{Regexp.escape(SPEC)}$/, @fixture.printed)
    assert_equal "row text", File.read(File.join(home, SPEC))
  end

  def test_a_second_sync_after_a_write_out_has_nothing_to_do
    plastic("sync")
    change_row(SPEC, "row text")
    plastic("sync")
    plastic("sync")

    assert_includes @fixture.printed, "nothing to do"
  end

  def test_dry_run_prints_the_actions_and_writes_nothing
    plastic("sync")
    change_row(SPEC, "row text")
    plastic("sync", "--dry-run")

    assert_match(/^write\s+#{Regexp.escape(SPEC)}$/, @fixture.printed)
    assert_includes File.read(File.join(home, SPEC)), "river"
  end

  def test_a_conflict_exits_three
    plastic("sync")
    change_row(SPEC, "row text")
    seed(SPEC, "file text\n")

    assert_equal 3, plastic("sync")
  end

  def test_a_conflict_prints_the_path_and_a_diff
    plastic("sync")
    change_row(SPEC, "row text")
    seed(SPEC, "file text\n")
    plastic("sync")

    assert_includes @fixture.warned, SPEC
    assert_includes @fixture.warned, "-row text"
    assert_includes @fixture.warned, "+file text"
  end

  def test_a_conflict_changes_neither_side
    plastic("sync")
    change_row(SPEC, "row text")
    seed(SPEC, "file text\n")
    seed("store/1--alpha/plan.md", "# A changed plan\n")
    plastic("sync")

    assert_equal "file text\n", File.read(File.join(home, SPEC))
    assert_equal "row text", row_body(SPEC)
    refute_includes row_body("store/1--alpha/plan.md"), "changed"
  end

  def test_checkout_restores_a_deleted_markdown_file_byte_for_byte
    plastic("sync")
    before = File.binread(File.join(home, SPEC))
    File.delete(File.join(home, SPEC))

    assert_equal 0, plastic("checkout")
    assert_equal before, File.binread(File.join(home, SPEC))
  end

  def test_checkout_restores_a_deleted_binary_byte_for_byte
    plastic("sync")
    File.delete(File.join(home, PNG))
    plastic("checkout")

    assert_equal BYTES, File.binread(File.join(home, PNG))
    assert_includes @fixture.printed, PNG
  end

  def test_checkout_leaves_a_changed_file_alone
    plastic("sync")
    seed(SPEC, "my edit\n")
    plastic("checkout")

    assert_equal "my edit\n", File.read(File.join(home, SPEC))
  end

  def test_checkout_without_databases_exits_one_and_names_sync
    assert_equal 1, plastic("checkout")
    assert_includes @fixture.warned, "plastic sync"
  end

  def test_sync_on_a_broken_database_exits_one
    plastic("sync")
    File.write(File.join(home, "knowledge_graph.db"), "not a database")

    assert_equal 1, plastic("sync")
  end

  def test_checkout_on_a_broken_database_exits_one
    plastic("sync")
    File.write(File.join(home, "references.db"), "not a database")

    assert_equal 1, plastic("checkout")
  end

  def test_a_store_with_no_index_has_no_intent_row
    File.delete(File.join(home, "projects", "acme", "INDEX.md"))
    plastic("sync")

    assert_equal [{"n" => 0}], sql("work_graph.db", "SELECT count(*) AS n FROM intent WHERE store = 'acme'")
  end

  def test_the_intent_table_fills_from_the_index_files
    plastic("sync")

    assert_equal [{"id" => "1", "store" => "global", "slug" => "alpha", "status" => "active", "title" => "Alpha"},
      {"id" => "2", "store" => "acme", "slug" => "beta", "status" => "active", "title" => "Beta"}],
      sql("work_graph.db", "SELECT id, store, slug, status, title FROM intent ORDER BY id")
  end

  def test_the_ledger_table_fills_from_the_savepoint_files
    plastic("sync")

    assert_equal [{"intent_id" => "1", "store" => "global", "at" => "2026-09-21T11:00:00Z", "stage" => "How", "text" => "plan written"}],
      sql("work_graph.db", "SELECT intent_id, store, at, stage, text FROM ledger WHERE stage = 'How'")
  end

  def test_the_references_rows_carry_the_intent_and_a_sha256
    plastic("sync")

    assert_equal [{"name" => PNG, "intent_id" => "1", "sha256" => Digest::SHA256.hexdigest(BYTES)}],
      sql("references.db", "SELECT name, intent_id, sha256 FROM sqlar")
  end

  def test_a_file_under_an_intent_with_no_index_line_is_an_orphan
    seed("store/9--ghost/spec.md", "# Ghost\n")
    plastic("sync")

    assert_equal ["global:9"], Plastic::StoreSync.orphans(home)
  end

  def test_the_doctor_warns_about_an_orphan
    seed("store/9--ghost/spec.md", "# Ghost\n")
    plastic("sync")
    result = Doctor.new(plastic_home: home).check_graph_links.first

    assert_equal "warn", result[:status]
    assert_equal ["global:9"], result[:details]
  end

  def test_the_doctor_passes_when_every_file_has_an_intent_row
    plastic("sync")

    assert_equal ["pass"], Doctor.new(plastic_home: home).check_graph_links.map { |result| result[:status] }
  end

  def test_the_doctor_skips_the_link_check_before_the_first_sync
    assert_empty Doctor.new(plastic_home: home).check_graph_links
  end

  def test_a_changed_binary_gets_a_new_sha256
    plastic("sync")
    seed(PNG, BYTES + "more".b)
    plastic("sync")

    assert_equal [{"sha256" => Digest::SHA256.hexdigest(BYTES + "more".b)}], sql("references.db", "SELECT sha256 FROM sqlar")
  end

  def test_an_index_line_under_another_heading_is_no_intent_row
    File.write(File.join(home, "INDEX.md"), "\n## Clusters\n\n- [1 — Alpha](store/1--alpha/1--alpha.md)\n", mode: "a")
    plastic("sync")

    assert_equal [{"n" => 1}], sql("work_graph.db", "SELECT count(*) AS n FROM intent WHERE id = '1'")
  end

  def test_a_session_resource_has_no_intent_id
    seed("store/.sessions/20260921/resources/report.html", "<p>report</p>")
    plastic("sync")

    assert_equal [{"intent_id" => nil}], sql("references.db", "SELECT intent_id FROM sqlar WHERE name LIKE '%report.html'")
  end

  def test_a_file_outside_resources_is_archived_and_a_lock_is_not
    seed("store/1--alpha/graph.yml", "nodes: []\n")
    seed("store/1--alpha/delivery.lock", "held\n")
    plastic("sync")

    assert_equal [{"name" => "store/1--alpha/graph.yml", "intent_id" => "1"}],
      sql("references.db", "SELECT name, intent_id FROM sqlar WHERE name LIKE 'store/1--alpha/%' AND name NOT LIKE '%resources%'")
  end

  def test_render_keeps_every_heading_and_table_cell
    seed("page.md", "# Title\n\n## Part\n\n| Name | Value |\n|---|---|\n| heron | 7 |\n")
    plastic("render", File.join(home, "page.md"))

    ["<h1", "Title", "<h2", "Part", "<th>Name</th>", "<th>Value</th>", "<td>heron</td>", "<td>7</td>"].each do |piece|
      assert_includes @fixture.printed, piece
    end
  end

  def test_render_carries_one_stylesheet
    seed("page.md", "# Title\n")
    plastic("render", File.join(home, "page.md"))

    assert_equal 1, @fixture.printed.scan("<style>").size
  end

  def test_render_without_a_file_exits_two
    assert_equal 2, plastic("render")
  end

  def test_render_with_a_missing_file_exits_one
    assert_equal 1, plastic("render", "/nowhere/page.md")
  end
end
