# frozen_string_literal: true

require_relative "../support/kernel"

class SyncTest < Minitest::Test
  include KernelFixtures::StoreCalls

  DIR = "store/1--alpha"
  FILE = "#{DIR}/1--alpha.md".freeze
  SPEC = "#{DIR}/spec.md".freeze
  GRAPH = { "intent" => "1", "nodes" => [{ "id" => "n1", "kind" => "build", "title" => "Build", "state" => "open" }],
            "edges" => [{ "from" => "n1", "to" => "n2", "kind" => "needs" }] }.freeze

  def setup
    super
    run_plastic("intent", "new", "Alpha")
    write(SPEC, "# Spec\n")
    run_plastic("sync", "up")
  end

  def write(path, text) = File.write(store_path(path), text)

  def read(path) = File.read(store_path(path))

  def change_row(path, body)
    store_graphs.databases[:knowledge].transaction do |batch|
      batch.put(:documents, { intent_id: "1", path: path.delete_prefix("#{DIR}/"), body:, updated_at: Plastic.now })
    end
  end

  def document(path) = store_graphs.retrieval.documents("1").find { |d| d.path == path.delete_prefix("#{DIR}/") }&.body

  def change_count = store_graphs.databases[:knowledge].row("SELECT count(*) AS n FROM changes")["n"]

  def both_changed(*paths) = paths.each { |path| write(path, "by hand\n") && change_row(path, "in rows\n") }

  def test_a_deleted_intent_folder_comes_back_the_same
    write("#{DIR}/graph.json", JSON.pretty_generate(GRAPH))
    assert_equal 0, run_plastic("sync", "up").code
    before = snapshot(store_path(DIR))
    FileUtils.rm_rf(store_path(DIR))
    call = run_plastic("sync", "down")

    assert_equal 0, call.code, call.err
    assert_equal before, snapshot(store_path(DIR))
    assert_includes before.keys, "graph.json"
  end

  def test_sync_up_reads_a_hand_edit_into_rows
    write(SPEC, "# Spec, edited\n")
    call = run_plastic("sync", "up")

    assert_equal 0, call.code, call.err
    assert_equal "# Spec, edited\n", document(SPEC)
  end

  def test_sync_up_skips_a_file_that_did_not_change
    before = change_count
    run_plastic("sync", "up")

    assert_equal before, change_count
  end

  def test_sync_up_reads_graph_json_into_nodes_and_edges
    write("#{DIR}/graph.json", JSON.generate(GRAPH))
    run_plastic("sync", "up")
    retrieval = store_graphs.retrieval

    assert_equal ["n1"], retrieval.nodes("1").map(&:id)
    assert_equal [%w[n1 n2 needs]], retrieval.edges("1").map { |edge| [edge.from, edge.to, edge.kind] }
  end

  def test_sync_down_prints_a_row_change
    change_row(SPEC, "# Spec from rows\n")
    call = run_plastic("sync", "down")

    assert_equal 0, call.code, call.err
    assert_equal "# Spec from rows\n", read(SPEC)
  end

  def test_plain_sync_writes_nothing_and_lists_every_conflict
    both_changed(SPEC, FILE)
    change_row("#{DIR}/notes.md", "new in rows\n")
    %w[up down].each do |direction|
      call = run_plastic("sync", direction)

      assert_equal 3, call.code
      assert_includes call.err, SPEC
      assert_includes call.err, FILE
    end
    assert_equal "by hand\n", read(SPEC)
    assert_equal "in rows\n", document(SPEC)
    refute_path_exists store_path("#{DIR}/notes.md")
  end

  def test_overwrite_with_a_path_takes_one_record
    both_changed(SPEC, FILE)
    call = run_plastic("sync", "down", "--overwrite", SPEC)

    assert_equal 3, call.code
    assert_equal "in rows\n", read(SPEC)
    assert_equal "by hand\n", read(FILE)
    assert_includes call.err, FILE
    refute_includes call.err, SPEC
  end

  def test_overwrite_alone_takes_the_direction_for_the_store
    both_changed(SPEC, FILE)
    call = run_plastic("sync", "up", "--overwrite")

    assert_equal 0, call.code, call.err
    assert_equal ["by hand\n", "by hand\n"], [document(SPEC), document(FILE)]
  end

  def test_overwrite_names_a_record_that_exists
    call = run_plastic("sync", "down", "--overwrite", "store/9--nothing/spec.md")

    assert_equal 1, call.code
    assert_includes call.err, "store/9--nothing/spec.md"
  end

  def test_merge_takes_one_sided_changes_and_refuses_the_rest
    both_changed(SPEC)
    change_row(FILE, "row only\n")
    call = run_plastic("sync", "down", "--merge")

    assert_equal 3, call.code
    assert_equal "row only\n", read(FILE)
    assert_equal "by hand\n", read(SPEC)
    assert_includes call.err, SPEC
    refute_includes call.err, FILE
  end
end
