# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeSyncTest < Plastic::TestCase
  fixtures :alpha_synced

  SPEC = "store/1--alpha/spec.md"
  FILE = "store/1--alpha/1--alpha.md"

  def sync = (@sync ||= Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases))

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
    assert_equal [[], [FILE]], [run_sync(:down), sync.printer.written]
    assert_equal ["# Edited\n", "from rows\n"], [body(SPEC), folder.read(FILE)]
  end

  def test_a_level_store_does_nothing_either_way
    assert_equal [[], []], [run_sync(:up), run_sync(:down)]
  end

  def test_a_merge_leaves_the_conflict_as_it_is
    write(SPEC, "by hand\n")
    change_row(SPEC, "in rows\n")
    change_row(FILE, "row only\n")

    assert_equal [], run_sync(:down, merge: true)
    assert_equal [FILE], sync.printer.written
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

  def with_legacy_plan
    store_graphs.databases[:knowledge].transaction do |batch|
      batch.put(:legacy_intents_data, { intent_id: "1", path: "plan.md", body: "# Plan\r\n", updated_at: STAMP })
    end
    run_sync(:down)
  end

  def test_sync_down_prints_a_legacy_plan_byte_for_byte
    with_legacy_plan

    assert_equal "# Plan\r\n", folder.read("store/1--alpha/plan.md")
  end

  def test_sync_down_prints_a_deleted_plan_back_from_its_legacy_row
    with_legacy_plan
    folder.delete("store/1--alpha/plan.md")

    assert_equal [], run_sync(:down)
    assert_equal ["store/1--alpha/plan.md"], sync.printer.written
  end

  def test_an_emptied_work_log_drops_its_lines_and_keeps_its_file
    write("store/1--alpha/work.log", "")

    assert_equal ["read store/1--alpha/work.log"], run_sync(:up)
    assert_equal [[], ""], [retrieval.work_log("1"), folder.read("store/1--alpha/work.log")]
  end

  def test_print_says_each_path_it_wrote
    print = Plastic::Graph::Prints::Print.text("store/1--alpha/notes.md", :knowledge, "n\n")

    assert_equal [["store/1--alpha/notes.md"], []], [sync.printer.print([print]), sync.printer.print([print])]
  end

  def test_a_sync_keeps_the_databases_out_of_versioning
    folder.delete(".gitignore")
    run_sync(:up)

    assert_equal "*.db\n*.db-journal\nbackups/\n", folder.read(".gitignore")
  end

  def test_a_level_file_with_no_record_is_recorded
    store_graphs.databases[:knowledge].transaction { |batch| batch.remove(:printed, path: SPEC) }

    assert_equal [], run_sync(:up)
    assert_equal Digest::SHA256.hexdigest("# Spec\n"), retrieval.printed[SPEC]
  end
end

class KnowledgeSyncIndexTest < Plastic::TestCase
  fixtures :alpha_synced

  SPEC = "store/1--alpha/spec.md"

  def sync = (@sync ||= Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases))

  def test_read_takes_an_intent_a_hand_edit_of_the_index_adds
    entry = retrieval.intent("1").index_h.merge("title" => "Renamed")
    write("store/index.json", JSON.generate({ "intents" => [entry] }))

    assert_equal ["read store/index.json"], sync.read(["store/index.json"])
    assert_equal "Renamed", retrieval.intent("1").title
  end

  def hand_edited_index_of_another_origin
    index = JSON.parse(folder.read("store/index.json"))
    index.fetch("intents").each { |entry| entry.merge!("origin_id" => "zzzz", "title" => "Renamed by hand") }
    write("store/index.json", JSON.pretty_generate(index))
  end

  def test_sync_up_names_an_index_it_cannot_read
    hand_edited_index_of_another_origin

    assert_equal ["store/index.json"], sync.plan(:up).unreadable_files.keys
  end

  def test_sync_up_leaves_an_index_it_cannot_read_as_it_is
    hand_edited_index_of_another_origin
    run = sync.apply(sync.plan(:up))

    assert_equal [[], "Alpha", true], [run, retrieval.intent("1").title, folder.read("store/index.json").include?("Renamed by hand")]
  end

  def foreign_index
    index = JSON.parse(folder.read("store/index.json"))
    index.fetch("intents").each { |entry| entry["origin_id"] = "zzzz" }
    write("store/index.json", JSON.pretty_generate(index.merge("origin_id" => "zzzz")))
  end

  def test_sync_up_prints_an_index_that_another_home_printed_from_the_rows
    foreign_index
    result = plastic("sync", "up", table: Plastic::CLI::TABLE)

    assert_equal [0, "", true, retrieval.origin_id], [result.code, result.err, result.out.include?("next: plastic next"),
      JSON.parse(folder.read("store/index.json")).fetch("origin_id")], result.out
  end

  def test_sync_up_plans_a_read_of_an_index_another_home_printed_when_this_home_holds_a_print_of_it
    foreign_index

    assert_equal [["store/index.json"], [], {}], [sync.plan(:up).entries_for(:read).map(&:path), sync.plan(:up).entries_for(:print).map(&:path), sync.plan(:up).unreadable_files]
  end

  def test_sync_up_names_an_index_that_is_a_json_array_as_a_file_it_cannot_read
    write("store/index.json", "[]")

    assert_equal ["store/index.json"], sync.plan(:up).unreadable_files.keys
  end

  def test_a_broken_index_does_not_stop_the_read_of_another_file
    write("store/index.json", "{")

    assert_equal ["read #{SPEC}"], sync.read([SPEC])
  end
end

# Step 24, the part row of the clusters: its path, its digest and its record in the printed table.
class KnowledgeSyncTwoHomesClusterPartTest < Plastic::TestCase
  include TwoHomesClusterHelper

  ClusterPart = Plastic::Graph::Prints::ClusterPart

  def test_the_digest_of_the_clusters_is_the_same_for_two_orders_of_the_same_clusters
    one = [{ "name" => "b", "intents" => %w[2 1] }, { "name" => "a", "intents" => ["3"] }]
    other = [{ "name" => "a", "intents" => ["3"] }, { "name" => "b", "intents" => %w[1 2] }]

    assert_equal ClusterPart.digest(one), ClusterPart.digest(other)
  end

  def test_one_intent_changed_on_the_second_home_is_no_change_of_the_clusters
    to_both_homes do |_a, b|
      call_in(b, "intent", "new", "Gamma")
      up = call_in(b, "sync", "up")
      down = call_in(b, "sync", "down")

      assert_equal [0, 0, [%w[one 1]]], [up.code, down.code, clusters(b)], said(up) + said(down)
    end
  end

  def test_a_part_with_no_printed_row_gives_no_conflict_and_the_next_print_writes_the_row
    to_both_homes do |_a, b|
      database_of(b, :work).transaction { |batch| batch.remove(:printed, path: PART) }
      up = call_in(b, "sync", "up")
      call_in(b, "sync", "down")

      assert_equal [0, true], [up.code, printed_part?(b)], said(up)
    end
  end

  def test_the_first_print_records_the_part_row
    to_both_homes do |a, _b|
      assert printed_part?(a)
    end
  end
end

# Step 24, the cluster kind: the clusters of an index that differ from their last print on a home that holds their rows are read into rows.
class KnowledgeSyncTwoHomesClusterTest < Plastic::TestCase
  include TwoHomesClusterHelper

  def test_a_change_on_the_first_home_reaches_the_rows_of_the_second_home
    to_both_homes do |a, b|
      change_clusters(a, "two", "2")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [%w[one 1], %w[two 2]], %w[one two]], [up.code, clusters(b), listed(b)], said(up)
    end
  end

  def test_a_second_sync_up_after_a_cluster_read_writes_nothing
    to_both_homes do |a, b|
      change_clusters(a, "two", "2")
      pull(b, a)
      call_in(b, "sync", "up")
      before = [files_snapshot(b), clusters(b)]
      again = call_in(b, "sync", "up")

      assert_equal [0, before], [again.code, [files_snapshot(b), clusters(b)]], said(again)
    end
  end

  def test_a_hand_edit_of_the_clusters_on_a_home_that_works_alone_is_read_into_rows
    with_home do |home|
      seed(home)
      call_in(home, "sync", "down")
      data = JSON.parse(read_file(home, FILE))
      write_file(home, FILE, JSON.pretty_generate(data.merge("clusters" => [{ "name" => "by hand", "intents" => %w[1 2] }])))
      up = call_in(home, "sync", "up")

      assert_equal [0, [["by hand", "1"], ["by hand", "2"]]], [up.code, clusters(home)], said(up)
    end
  end

  def test_the_same_change_on_both_homes_is_recorded_and_is_no_conflict
    to_both_homes do |a, b|
      change_clusters(a, "same", "1")
      put_cluster(b, "same", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [%w[one 1], %w[same 1]]], [up.code, clusters(b)], said(up)
    end
  end

  def test_clusters_that_cannot_be_read_are_left_as_written_listed_and_the_rows_stay
    to_both_homes do |_a, b|
      data = JSON.parse(read_file(b, FILE))
      write_file(b, FILE, JSON.pretty_generate(data.merge("clusters" => [{ "name" => "bad", "intents" => "1" }])))
      written = read_file(b, FILE)
      up = call_in(b, "sync", "up")

      assert_equal [1, written, [%w[one 1]], true], [up.code, read_file(b, FILE), clusters(b), said(up).include?("sync down --overwrite #{FILE}")], said(up)
    end
  end

  def test_an_index_deleted_on_the_first_home_is_printed_again_on_the_second_home_by_sync_down
    to_both_homes do |a, b|
      File.delete(File.join(store_of(a), FILE))
      pull(b, a)
      down = call_in(b, "sync", "down")

      assert_equal [0, true, [%w[one 1]]], [down.code, File.exist?(File.join(store_of(b), FILE)), clusters(b)], said(down)
    end
  end

  def test_a_home_that_holds_no_rows_for_the_clusters_reads_the_file_as_the_older_step_does
    two_homes do |a, b|
      seed(a)
      call_in(a, "sync", "down")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [%w[one 1]]], [up.code, clusters(b)], said(up)
    end
  end

  def test_a_cluster_read_leaves_the_rows_of_another_origin_and_duplicates_no_row
    to_both_homes do |a, b|
      put_cluster(b, "foreign", "1", origin: "zzz-other")
      call_in(b, "sync", "down")
      change_clusters(a, "two", "2")
      pull(b, a)
      2.times { call_in(b, "sync", "up") }

      assert_equal [[%w[one 1], %w[two 2]], [%w[foreign 1]]], [clusters(b), clusters(b, origin: "zzz-other")]
    end
  end

  def test_the_part_of_the_clusters_gets_no_file_and_sync_down_writes_none_with_a_hash_in_its_name
    to_both_homes do |a, _b|
      change_clusters(a, "two", "2")

      assert_equal [], files_of(a).select { |rel| rel.include?("#") }
    end
  end
end

# Step 24, the context kind: a file changed and rows changed without a print are a conflict, and the three ways to settle it.
class KnowledgeSyncTwoHomesContextConflictTest < Plastic::TestCase
  include TwoHomesContextHelper

  # B's rows changed with no print, and A's changed file arrived.
  def conflicting
    to_both_homes do |a, b|
      change_part(a, "context", { "note" => "from A" })
      put_part(b, "context", { "note" => "row of B" })
      pull(b, a)
      yield b
    end
  end

  def test_a_context_file_changed_and_rows_changed_without_a_print_are_a_conflict_that_writes_nothing
    conflicting do |b|
      rows = part_of(b, "context")
      files = files_snapshot(b)
      up = call_in(b, "sync", "up")

      assert_equal [3, true, rows, files], [up.code, said(up).include?(FILE), part_of(b, "context"), files_snapshot(b)], said(up)
    end
  end

  def test_overwrite_of_the_path_on_sync_up_reads_the_file_and_settles_the_conflict
    conflicting do |b|
      up = call_in(b, "sync", "up", "--overwrite", FILE)

      assert_equal [0, { "note" => "from A" }], [up.code, part_of(b, "context")], said(up)
    end
  end

  def test_overwrite_of_the_path_on_sync_down_prints_the_rows_over_the_file
    conflicting do |b|
      down = call_in(b, "sync", "down", "--overwrite", FILE)

      assert_equal [0, "row of B"], [down.code, file_part(b, "context")["note"]], said(down)
    end
  end

  def test_merge_lists_the_conflict_of_a_context_and_exits_as_a_refusal
    conflicting do |b|
      up = call_in(b, "sync", "up", "--merge")

      assert_equal [3, true], [up.code, said(up).include?(FILE)], said(up)
    end
  end
end

# Step 24, the context kind: a context.json that differs from its last print on a home that holds its rows is read into rows.
class KnowledgeSyncTwoHomesContextTest < Plastic::TestCase
  include TwoHomesContextHelper

  def test_a_change_on_the_first_home_reaches_the_rows_of_the_second_home
    to_both_homes do |a, b|
      change_part(a, "context", { "note" => "from A" })
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, { "note" => "from A" }, "from A"], [up.code, part_of(b, "context"), file_part(b, "context")["note"]], said(up)
    end
  end

  def test_a_second_sync_up_after_a_context_read_writes_nothing
    to_both_homes do |a, b|
      change_part(a, "context", { "note" => "from A" })
      pull(b, a)
      call_in(b, "sync", "up")
      before = [files_snapshot(b), part_of(b, "context")]
      again = call_in(b, "sync", "up")

      assert_equal [0, before], [again.code, [files_snapshot(b), part_of(b, "context")]], said(again)
    end
  end

  def test_a_hand_edit_of_a_context_file_on_a_home_that_works_alone_is_read_into_rows
    with_home do |home|
      seed(home)
      call_in(home, "sync", "down")
      write_file(home, FILE, JSON.generate(JSON.parse(read_file(home, FILE)).merge("context" => { "note" => "by hand" })))
      up = call_in(home, "sync", "up")

      assert_equal [0, { "note" => "by hand" }], [up.code, part_of(home, "context")], said(up)
    end
  end

  def test_the_same_change_on_both_homes_is_recorded_and_is_no_conflict
    to_both_homes do |a, b|
      change_part(a, "context", { "note" => "same" })
      put_part(b, "context", { "note" => "same" })
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, { "note" => "same" }], [up.code, part_of(b, "context")], said(up)
    end
  end

  def test_a_context_file_that_cannot_be_read_is_left_as_written_listed_and_the_rows_stay
    to_both_homes do |_a, b|
      write_file(b, FILE, "not json\n")
      rows = part_of(b, "context")
      up = call_in(b, "sync", "up")

      assert_equal [1, "not json\n", rows, true], [up.code, read_file(b, FILE), part_of(b, "context"), said(up).include?("sync down --overwrite #{FILE}")], said(up)
    end
  end

  def test_a_context_file_deleted_on_the_first_home_is_printed_again_on_the_second_home_by_sync_down
    to_both_homes do |a, b|
      File.delete(File.join(store_of(a), FILE))
      pull(b, a)
      down = call_in(b, "sync", "down")

      assert_equal [0, true], [down.code, File.exist?(File.join(store_of(b), FILE))], said(down)
    end
  end

  def test_a_home_that_holds_no_rows_for_the_context_reads_the_file_as_the_older_step_does
    two_homes do |a, b|
      seed(a)
      call_in(a, "sync", "down")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, { "note" => "first" }], [up.code, part_of(b, "context")], said(up)
    end
  end

  def test_a_context_read_leaves_the_rows_of_another_origin_and_duplicates_no_row
    to_both_homes do |a, b|
      put_part(b, "context", { "note" => "foreign" }, origin: "zzz-other")
      change_part(a, "context", { "note" => "from A" })
      pull(b, a)
      2.times { call_in(b, "sync", "up") }

      assert_equal [{ "note" => "from A" }, { "note" => "foreign" }], [part_of(b, "context"), part_of(b, "context", origin: "zzz-other")]
    end
  end

  def test_a_context_file_that_only_the_first_home_printed_gets_an_entry
    two_homes do |a, b|
      seed(a)
      call_in(a, "sync", "down")
      pull(b, a)

      assert_includes Plastic::Graph::Knowledge::Sync::EntryList.new(folder_of(b), home_graphs(b).retrieval).on_disk, FILE
    end
  end
end

# Step 27: links changed on both homes, a part that cannot be read and an index with no links part.
class KnowledgeSyncTwoHomesLinksChangesTest < Plastic::TestCase
  include TwoHomesLinksHelper

  def test_the_same_link_made_on_both_homes_at_two_times_is_recorded_and_is_no_conflict
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      put_link(b, "2", "cites", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [CITES], true], [up.code, links(b), printed_part?(b)], said(up)
    end
  end

  def test_links_changed_on_both_homes_to_other_keys_are_a_conflict_and_neither_the_rows_nor_the_file_change
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      put_link(b, "2", "source", "1")
      pull(b, a)
      before = files_snapshot(b)
      up = call_in(b, "sync", "up")

      assert_equal [3, [%w[2 1 source]], before], [up.code, links(b), files_snapshot(b)], said(up)
    end
  end

  def test_a_links_part_with_a_kind_outside_the_kinds_is_left_listed_with_its_reason_and_the_rows_stay
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      pull(b, a)
      write_links_part(b, [{ "from_ref" => "2", "to_ref" => "1", "kind" => "no-such-kind", "at" => "x" }])
      up = call_in(b, "sync", "up")

      assert_equal [1, [], true, false], [up.code, links(b), said(up).include?("no-such-kind"), said(up).match?(/Invalid|NoMethodError/)], said(up)
    end
  end

  def test_an_index_with_no_links_part_leaves_every_link_in_the_rows_and_sync_down_then_prints_the_part
    to_both_homes do |a, _b|
      link(a, "2", "cites", "1")
      write_links_part(a, nil)
      up = call_in(a, "sync", "up")
      down = call_in(a, "sync", "down")

      assert_equal [0, [CITES], 0, [CITES]], [up.code, links(a), down.code, listed_keys(a)], said(up) + said(down)
    end
  end
end

# Step 27: what a read keeps as written, the links of another origin and a home that holds links with no part row.
class KnowledgeSyncTwoHomesLinksKeptTest < Plastic::TestCase
  include TwoHomesLinksHelper

  ENDS = [%w[2 1/D1 cites], %w[2 9 cites], %w[2 global:25 cites]].freeze

  def test_a_link_to_a_ruling_to_a_ref_of_another_store_and_to_an_archived_intent_is_kept_as_written
    to_both_homes do |a, b|
      ENDS.each { |from, to, kind| put_link(a, from, kind, to) }
      call_in(a, "sync", "down")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, ENDS.sort], [up.code, links(b)], said(up)
    end
  end

  def test_a_read_leaves_the_links_of_another_origin_and_a_second_read_duplicates_no_row
    to_both_homes do |a, b|
      put_link(b, "2", "source", "1", origin: "zzzz")
      link(a, "2", "cites", "1")
      pull(b, a)
      call_in(b, "sync", "up")
      call_in(b, "sync", "up")

      assert_equal [[CITES], [%w[2 1 source]]], [links(b), links(b, origin: "zzzz")]
    end
  end

  def test_a_home_that_holds_links_and_no_part_row_keeps_its_own_adds_the_links_of_the_file_and_prints_both
    to_both_homes do |a, b|
      put_link(b, "1", "chain", "2")
      forget_part(b)
      link(a, "2", "cites", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [%w[1 2 chain], CITES], [%w[1 2 chain], CITES], true], [up.code, links(b), listed_keys(b), printed_part?(b)], said(up)
    end
  end
end

# Step 27: the links between intents are a part of store/index.json, printed by every link command and read by sync up.
class KnowledgeSyncTwoHomesLinksTest < Plastic::TestCase
  include TwoHomesLinksHelper

  def test_a_link_command_prints_an_index_that_lists_the_link_and_records_the_part_row
    to_both_homes do |a, _b|
      link(a, "2", "cites", "1")

      assert_equal [[CITES], true], [listed_keys(a), printed_part?(a)]
    end
  end

  def test_a_copy_on_a_home_with_no_rows_reads_the_links_of_the_files
    to_both_homes do |a, _b|
      link(a, "2", "cites", "1")
      with_home do |c|
        pull(c, a)
        up = call_in(c, "sync", "up")

        assert_equal [0, [CITES]], [up.code, links(c)], said(up)
      end
    end
  end

  def test_a_home_whose_databases_were_removed_reads_its_links_back_from_its_files
    with_home do |home|
      seed(home)
      link(home, "2", "source", "1")
      Plastic::Graph::Database::ConnectionPool.release(File.dirname(home))
      Dir.glob(File.join(store_of(home), "*.db*")).each { |file| File.delete(file) }
      up = call_in(home, "sync", "up")

      assert_equal [0, [%w[2 1 source]]], [up.code, links(home)], said(up)
    end
  end

  def test_a_link_made_on_the_first_home_reaches_the_second_home_and_a_second_sync_up_writes_nothing
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")
      before = files_snapshot(b)
      again = call_in(b, "sync", "up")

      assert_equal [0, [CITES], 0, before], [up.code, links(b), again.code, files_snapshot(b)], said(up) + said(again)
    end
  end

  def test_a_link_removed_on_the_first_home_is_gone_on_the_second_home_after_sync_up
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      pull(b, a)
      call_in(b, "sync", "up")
      held = links(b)
      unlink(a, "2", "cites", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [[CITES], 0, []], [held, up.code, links(b)], said(up)
    end
  end

  def test_an_intent_that_a_live_intent_links_to_on_the_first_home_stays_unarchived_on_the_second_home
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      close_intent(a, "1")
      pull(b, a)
      call_in(b, "sync", "up")
      archive = call_in(b, "intent", "archive", "--older-than", "2099-01-01")

      assert_equal [0, []], [archive.code, home_graphs(b).retrieval.archive_rows.map(&:intent_id)], said(archive)
    end
  end

  private

  def close_intent(home, intent_id)
    row = home_graphs(home).retrieval.intent(intent_id).new_row.merge(TwoHomesStatusHelper::CLOSED)
    database_of(home, :knowledge).transaction { |batch| batch.put(:intents, row) }
    call_in(home, "sync", "down")
  end
end

# Step 24, the roadmap kind: a file changed and rows changed without a print are a conflict, and the three ways to settle it.
class KnowledgeSyncTwoHomesRoadmapConflictTest < Plastic::TestCase
  include TwoHomesRoadmapHelper

  # B's rows changed with no print, and A's changed file arrived.
  def conflicting
    to_both_homes do |a, b|
      call_in(a, "roadmap", "log", "r1", "note from A")
      put_log(b, position: 50, text: "row of B")
      pull(b, a)
      yield b
    end
  end

  def test_a_roadmap_file_changed_and_rows_changed_without_a_print_are_a_conflict_that_writes_nothing
    conflicting do |b|
      rows = logs(b)
      files = files_snapshot(b)
      up = call_in(b, "sync", "up")

      assert_equal [3, true, rows, files], [up.code, said(up).include?(FILE), logs(b), files_snapshot(b)], said(up)
    end
  end

  def test_overwrite_of_the_path_on_sync_up_reads_the_file_and_settles_the_conflict
    conflicting do |b|
      up = call_in(b, "sync", "up", "--overwrite", FILE)

      assert_equal [0, true, false], [up.code, logs(b).include?("note from A"), logs(b).include?("row of B")], said(up)
    end
  end

  def test_overwrite_of_the_path_on_sync_down_prints_the_rows_over_the_file
    conflicting do |b|
      down = call_in(b, "sync", "down", "--overwrite", FILE)

      assert_equal [0, true, false], [down.code, read_file(b, FILE).include?("row of B"), read_file(b, FILE).include?("note from A")], said(down)
    end
  end

  def test_merge_lists_the_conflict_of_a_roadmap_and_exits_as_a_refusal
    conflicting do |b|
      up = call_in(b, "sync", "up", "--merge")

      assert_equal [3, true], [up.code, said(up).include?(FILE)], said(up)
    end
  end
end

# Step 24, the roadmap kind: a roadmap file that differs from its last print on a home that holds its rows is read into rows.
class KnowledgeSyncTwoHomesRoadmapTest < Plastic::TestCase
  include TwoHomesRoadmapHelper

  def test_a_change_on_the_first_home_reaches_the_rows_of_the_second_home
    to_both_homes do |a, b|
      call_in(a, "roadmap", "log", "r1", "note from A")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, true, true], [up.code, logs(b).include?("note from A"), read_file(b, FILE).include?("note from A")], said(up)
    end
  end

  def test_a_second_sync_up_after_a_roadmap_read_writes_nothing
    to_both_homes do |a, b|
      call_in(a, "roadmap", "log", "r1", "note from A")
      pull(b, a)
      call_in(b, "sync", "up")
      before = [files_snapshot(b), logs(b)]
      again = call_in(b, "sync", "up")

      assert_equal [0, before], [again.code, [files_snapshot(b), logs(b)]], said(again)
    end
  end

  def test_a_hand_edit_of_a_roadmap_file_on_a_home_that_works_alone_is_read_into_rows
    with_home do |home|
      seed(home)
      write_file(home, FILE, read_file(home, FILE).sub(/^goal: A goal$/, "goal: by hand"))
      up = call_in(home, "sync", "up")

      assert_equal [0, "by hand"], [up.code, goal(home)], said(up)
    end
  end

  def test_the_same_change_on_both_homes_is_recorded_and_is_no_conflict
    to_both_homes do |a, b|
      call_in(a, "roadmap", "log", "r1", "same note")
      put_log(b, rows_of(a, :work, "SELECT position, at, text, session_id FROM roadmap_log WHERE text = 'same note'").first.transform_keys(&:to_sym))
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, 1], [up.code, logs(b).count("same note")], said(up)
    end
  end

  def test_a_roadmap_file_that_cannot_be_read_is_left_as_written_listed_and_the_rows_stay
    to_both_homes do |_a, b|
      write_file(b, FILE, "not a roadmap\n")
      rows = logs(b)
      up = call_in(b, "sync", "up")

      assert_equal [1, "not a roadmap\n", rows, true], [up.code, read_file(b, FILE), logs(b), said(up).include?("sync down --overwrite #{FILE}")], said(up)
    end
  end

  def test_a_roadmap_file_deleted_on_the_first_home_is_printed_again_on_the_second_home_by_sync_down
    to_both_homes do |a, b|
      File.delete(File.join(store_of(a), FILE))
      pull(b, a)
      down = call_in(b, "sync", "down")

      assert_equal [0, true], [down.code, File.exist?(File.join(store_of(b), FILE))], said(down)
    end
  end

  def test_a_home_that_holds_no_rows_for_the_roadmap_reads_the_file_as_the_older_step_does
    two_homes do |a, b|
      seed(a)
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, ["Road"]], [up.code, rows_of(b, :work, "SELECT title FROM roadmaps WHERE slug = 'r1'").map { |row| row["title"] }], said(up)
    end
  end

  def test_a_roadmap_read_leaves_the_rows_of_another_origin_and_duplicates_no_row
    to_both_homes do |a, b|
      put_log(b, position: 90, text: "foreign", origin_id: "other-origin")
      call_in(a, "roadmap", "log", "r1", "note from A")
      pull(b, a)
      2.times { call_in(b, "sync", "up") }

      assert_equal [1, 1], [logs(b).count("note from A"), logs(b).count("foreign")]
    end
  end

  def test_a_roadmap_file_that_only_the_first_home_printed_gets_an_entry
    two_homes do |a, b|
      seed(a)
      pull(b, a)

      assert_includes Plastic::Graph::Knowledge::Sync::EntryList.new(folder_of(b), home_graphs(b).retrieval).on_disk, FILE
    end
  end
end

# Step 26: the title and the state of an intent in an index that another home printed, on a home that holds a print of the index.
class KnowledgeSyncTwoHomesStatusTest < Plastic::TestCase
  include TwoHomesStatusHelper

  def test_a_retitle_on_the_first_home_reaches_the_row_of_the_second_home
    to_both_homes do |a, b|
      change_row(a, "1", title: "Retitled by A")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, "Retitled by A"], [up.code, fields(b, "1")["title"]], said(up)
    end
  end

  def test_a_close_with_a_reason_on_the_first_home_reaches_the_row_of_the_second_home
    to_both_homes do |a, b|
      change_row(a, "1", **CLOSED)
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, fields(a, "1")], [up.code, fields(b, "1")], said(up)
    end
  end

  def test_a_field_that_does_not_cross_keeps_the_value_of_the_second_home
    to_both_homes do |a, b|
      change_row(b, "1", ref: "ticket-7")
      change_row(a, "1", title: "Retitled by A", ref: "ticket-9")
      pull(b, a)
      call_in(b, "sync", "up")

      assert_equal ["ticket-7", "Retitled by A"], [intent_row(b, "1")["ref"], intent_row(b, "1")["title"]]
    end
  end

  def test_an_entry_whose_intent_has_no_folder_on_the_second_home_gives_no_row
    to_both_homes do |a, b|
      call_in(a, "intent", "new", "Gamma")
      write_file(b, FILE, read_file(a, FILE))
      up = call_in(b, "sync", "up")

      assert_equal [0, nil], [up.code, intent_row(b, "3")], said(up)
    end
  end

  def test_an_entry_of_a_third_origin_is_refused_listed_and_leaves_the_rows
    to_both_homes do |a, b|
      change_row(a, "1", title: "Retitled by A")
      pull(b, a)
      list_first_intent_of_a_third_origin(b)
      up = call_in(b, "sync", "up")

      assert_equal [1, "Alpha", true], [up.code, fields(b, "1")["title"], said(up).include?("sync down --overwrite #{FILE}")], said(up)
    end
  end

  def test_a_copy_on_a_home_with_no_print_of_the_index_takes_the_titles_of_the_folders
    to_both_homes do |a, _b|
      change_row(a, "1", title: "Retitled by A")
      with_home do |c|
        pull(c, a)
        up = call_in(c, "sync", "up")

        assert_equal [0, "Retitled by A"], [up.code, fields(c, "1")["title"]], said(up)
      end
    end
  end

  def test_after_the_read_the_index_carries_the_origin_of_the_second_home_and_a_second_sync_up_writes_nothing
    to_both_homes do |a, b|
      change_row(a, "1", **CLOSED)
      pull(b, a)
      call_in(b, "sync", "up")
      before = files_snapshot(b)
      again = call_in(b, "sync", "up")

      assert_equal [0, origin_of(b), before], [again.code, index_of(b)["origin_id"], files_snapshot(b)], said(again)
    end
  end

  def test_a_hand_edit_of_a_title_in_the_own_index_of_a_home_that_works_alone_is_read
    with_home do |home|
      seed(home)
      call_in(home, "sync", "down")
      data = index_of(home)
      data["intents"].first["title"] = "By hand"
      write_file(home, FILE, JSON.pretty_generate(data))
      up = call_in(home, "sync", "up")

      assert_equal [0, "By hand"], [up.code, fields(home, "1")["title"]], said(up)
    end
  end
end
