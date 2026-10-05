# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeSyncTest < Plastic::TestCase
  fixtures :alpha_synced

  SPEC = "store/1--alpha/spec.md"
  FILE = "store/1--alpha/1--alpha.md"

  def sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases)

  def run_sync(direction, **options) = sync.apply(sync.plan(direction, options))

  def change_row(path, body)
    store_graphs.databases[:knowledge].transaction do |batch|
      batch.put(:documents, { intent_id: "1", path: File.basename(path), body:, updated_at: STAMP })
    end
  end

  def body(path) = retrieval.documents("1").find { |document| document.path == File.basename(path) }&.body

  def test_the_plan_keeps_the_direction_and_the_overwrite_path_inside_the_store
    plan = sync.plan(:down, { overwrite: File.join(store_root, SPEC), merge: true })

    assert_equal [:down, true, []], [plan.direction, plan.merging?, plan.conflicts]
    assert_nil plan.failure
  end

  def test_up_reads_a_hand_edit_and_down_prints_a_row_change
    write(SPEC, "# Edited\n")
    change_row(FILE, "from rows\n")

    assert_equal ["read #{SPEC}"], run_sync(:up)
    assert_equal ["printed #{FILE}"], run_sync(:down)
    assert_equal ["# Edited\n", "from rows\n"], [body(SPEC), folder.read(FILE)]
  end

  def test_a_level_store_does_nothing_either_way
    assert_equal [[], []], [run_sync(:up), run_sync(:down)]
  end

  def test_a_merge_leaves_the_conflict_as_it_is
    write(SPEC, "by hand\n")
    change_row(SPEC, "in rows\n")
    change_row(FILE, "row only\n")

    assert_equal ["printed #{FILE}"], run_sync(:down, merge: true)
    assert_equal ["by hand\n", "in rows\n"], [folder.read(SPEC), body(SPEC)]
  end

  def test_an_overwrite_takes_the_side_of_the_direction
    write(SPEC, "by hand\n")
    change_row(SPEC, "in rows\n")

    assert_equal ["read #{SPEC}"], run_sync(:up, overwrite: nil)
    assert_equal "by hand\n", body(SPEC)
  end

  def test_a_deleted_folder_prints_back_the_same
    before = snapshot(store_path("store/1--alpha"))
    FileUtils.rm_rf(store_path("store/1--alpha"))
    run_sync(:down)

    assert_equal before, snapshot(store_path("store/1--alpha"))
  end

  def test_an_emptied_savepoint_drops_its_lines_and_keeps_its_file
    write("store/1--alpha/savepoint.md", "")

    assert_equal ["read store/1--alpha/savepoint.md"], run_sync(:up)
    assert_equal [[], ""], [retrieval.savepoints("1"), folder.read("store/1--alpha/savepoint.md")]
  end

  def test_read_takes_an_intent_a_hand_edit_of_the_index_adds
    entry = retrieval.intent("1").index_h.merge("title" => "Renamed")
    write("store/index.json", JSON.generate({ "intents" => [entry] }))

    assert_equal ["read store/index.json"], sync.read(["store/index.json"])
    assert_equal "Renamed", retrieval.intent("1").title
  end

  def test_an_index_that_does_not_parse_is_refused
    write("store/index.json", "{")
    error = assert_raises(Plastic::Invalid) { sync.read([SPEC]) }

    assert_match(/\Astore\/index.json does not parse: /, error.message)
  end

  def test_print_says_each_path_it_wrote
    print = Plastic::Graph::Prints::Print.text("store/1--alpha/notes.md", :knowledge, "n\n")

    assert_equal [["printed store/1--alpha/notes.md"], []], [sync.print([print]), sync.print([print])]
  end

  def test_a_sync_keeps_the_databases_out_of_versioning
    folder.delete(".gitignore")
    run_sync(:up)

    assert_equal "*.db\n*.db-journal\n", folder.read(".gitignore")
  end

  def test_a_level_file_with_no_record_is_recorded
    store_graphs.databases[:knowledge].transaction { |batch| batch.remove(:printed, path: SPEC) }

    assert_equal [], run_sync(:up)
    assert_equal Digest::SHA256.hexdigest("# Spec\n"), retrieval.printed[SPEC]
  end

  def list_beta_in_the_index
    data = JSON.parse(folder.read("store/index.json"))
    data["intents"] << data["intents"].first.merge("intent_id" => "2", "slug" => "beta", "title" => "Beta")
    write("store/index.json", JSON.generate(data))
  end

  def test_read_takes_a_folder_whose_intent_only_the_index_lists
    list_beta_in_the_index
    write("store/2--beta/spec.md", "# Beta\n")
    sync.read(["store/index.json", "store/2--beta/spec.md"])

    assert_equal ["# Beta\n"], retrieval.documents("2").map(&:body)
  end
end
