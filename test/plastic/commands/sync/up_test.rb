# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/sync/up"
require "json"
require_relative "../../../test_helpers/delivered_homes"
require_relative "../../../test_helpers/two_homes"
require_relative "../../../../lib/plastic/commands/roadmap/show"

class SyncUpTest < Plastic::TestCase
  fixtures :legacy

  def import = plastic("sync", "up", table: Plastic::CLI::TABLE)

  def legacy_metadata
    write("roadmaps/ship.md", "# Ship\n\n## Batches\n\n- [ ] 1 Build alpha — queued\n")
    write("store/1--alpha-service/spec.md", "# Spec\n\n## Decisions\n- D1 Keep local ownership\n")
  end

  def test_sync_up_offers_the_next_action_once_the_rows_hold_the_files
    legacy_metadata

    assert_call import, code: 0,
      out: ["imported INDEX.md: 2 intents", "next: plastic next\nbecause: the rows hold every file changed by hand\n"]
  end

  def test_sync_up_imports_legacy_rulings_and_links_together
    legacy_metadata
    import

    assert_equal ["D1 Keep local ownership"], retrieval.rulings("1").map(&:text)
    assert retrieval.links("1").any? { |link| link.kind == "source" && link.to_ref == "global:51" }
  end

  def test_sync_up_imports_the_roadmap
    legacy_metadata
    import

    assert_equal ["1"], retrieval.roadmap_items("ship").map(&:intent_id)
  end

  def test_sync_up_wrote_line_names_the_rows_and_leaves_out_the_routine_run
    result = import

    assert_includes result.out, "wrote:  2 intents and 2 savepoint lines in work_graph.db"
    refute_includes result.out, "routine run"
  end

  def test_preview_does_not_import_the_original_store
    before = snapshot(store_root)
    result = plastic("sync", "up", "--dry-run", table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: ["preview"]
    assert_equal before, snapshot(store_root)
  end
end

# Sync up reads every intent folder, whatever store/index.json says.
class SyncUpFoldersTest < Plastic::TestCase
  def sync = plastic("sync", "up", table: Plastic::CLI::TABLE)

  def page(id, title) = "---\nid: #{id.to_json}\nintent: #{title.to_json}\ncreated: #{STAMP.to_json}\n---\n\n# #{id} - #{title}\n"

  def hand_folder(id, slug, title)
    write("store/#{id}--#{slug}/#{id}--#{slug}.md", page(id, title))
    write("store/#{id}--#{slug}/spec.md", "# Spec #{title}\n")
  end

  # An intent made in the store "src", its files copied into the global store.
  def copy_from_src(title)
    source = Plastic::Graph.create(home: @plastic_home, store: "src")
    intent = source.work.write_intent(title:)
    source.work.print_intent(intent.intent_id)
    root = File.join(@plastic_home, "stores", "src")
    Dir.glob("store/**/*", base: root).select { |rel| File.file?(File.join(root, rel)) }
      .each { |rel| write(rel, File.binread(File.join(root, rel))) }
    intent
  end

  def add_ghost_to_index
    data = JSON.parse(folder.read("store/index.json"))
    data["intents"] << data["intents"].first.merge("intent_id" => "2", "slug" => "ghost", "title" => "Ghost")
    write("store/index.json", JSON.generate(data))
  end

  def intent_ids =retrieval.intents.map(&:intent_id)

  def index_ids = JSON.parse(folder.read("store/index.json"))["intents"].map { |entry| entry["intent_id"] }

  def document_bodies(intent_id)
    store_graphs.databases[:knowledge].rows("SELECT body FROM documents WHERE intent_id = '#{intent_id}' AND path = 'spec.md'")
      .map { |row| row["body"] || row[:body] }
  end

  def test_a_folder_with_no_row_and_no_index_entry_is_read_into_rows
    hand_folder("2", "beta", "Beta")

    assert_equal 0, sync.code
    assert_equal ["Beta"], retrieval.intents.map(&:title)
    assert_equal ["# Spec Beta\n"], document_bodies("2")
  end

  def test_rows_that_are_empty_while_the_index_lists_the_folders_are_rebuilt_with_no_flag
    copy_from_src("First")

    assert_equal 0, sync.code
    assert_equal ["1"], intent_ids
  end

  def test_an_index_entry_whose_folder_is_gone_gets_no_row_and_the_index_is_printed_again
    copy_from_src("First")
    add_ghost_to_index

    assert_equal 0, sync.code
    assert_equal [["1"], ["1"]], [intent_ids, index_ids]
  end

  def test_one_unreadable_folder_among_good_ones_fails_after_the_good_ones_are_read
    hand_folder("2", "beta", "Beta")
    write("store/7--stray/spec.md", "# Stray\n")
    result = sync

    assert_equal 1, result.code
    assert_equal ["2"], intent_ids
    assert_match(%r{store/7--stray.*no intent file}, result.err)
  end

  def test_an_intent_file_that_does_not_parse_is_named_with_its_reason
    write("store/8--bad/8--bad.md", "no front matter here\n")
    result = sync

    assert_equal 1, result.code
    assert_match(%r{store/8--bad.*does not parse}, result.err)
  end

  def test_two_folders_with_one_number_are_both_named_and_neither_is_read
    hand_folder("3", "one", "One")
    hand_folder("3", "two", "Two")
    result = sync

    assert_equal 1, result.code
    assert_empty intent_ids
    assert_match(%r{store/3--one.*store/3--two}m, result.err)
  end

  def test_a_second_sync_up_after_the_read_changes_nothing
    hand_folder("2", "beta", "Beta")
    sync
    before = snapshot(store_root)

    assert_equal 0, sync.code
    assert_equal before, snapshot(store_root)
  end

  def test_a_folder_holding_only_the_dated_intent_file_is_read
    write("store/4--gamma/4--gamma.md", page("4", "Gamma"))

    assert_equal 0, sync.code
    assert_equal ["Gamma"], retrieval.intents.map(&:title)
  end

  def test_a_folder_holding_only_intent_md_is_read
    write("store/5--delta/intent.md", page("5", "Delta"))

    assert_equal 0, sync.code
    assert_equal ["Delta"], retrieval.intents.map(&:title)
  end

  def test_a_printed_context_json_with_no_row_is_read_into_a_context_row_and_not_as_a_document
    hand_folder("2", "beta", "Beta")
    write("store/2--beta/context.json", JSON.generate("intent" => "2", "context" => { "forged" => true }))
    sync

    assert_equal [0, 1], [store_graphs.databases[:knowledge].rows("SELECT * FROM documents WHERE path = 'context.json'").size,
      store_graphs.databases[:knowledge].rows("SELECT * FROM retrieval_contexts").size]
  end
end

class SyncUpGeneratedTest < Plastic::TestCase
  include LifecycleHelper

  def index_path = store_path("store/index.json")

  def index_with_cluster
    data = JSON.parse(File.read(index_path))
    write("store/index.json", JSON.generate(data.merge("clusters" => [{ "name" => "imported", "intents" => ["1"] }])))
  end

  def test_sync_up_keeps_a_context_file_that_has_no_rows
    intent = open_intent
    path = "#{intent.dir}/context.json"
    write(path, "{}\n")
    result = cli("sync", "up")

    assert_equal [0, "{}\n"], [result.code, File.read(store_path(path))], result.err
  end

  def test_sync_up_prints_a_generated_index_with_other_content_and_leaves_it_level
    open_intent
    index_with_cluster
    result = cli("sync", "up")
    printed = File.read(index_path)

    assert_equal [0, "#{JSON.pretty_generate(JSON.parse(printed))}\n", true], [result.code, printed, printed.include?("imported")], result.err
  end

  def test_a_preview_of_sync_up_counts_the_generated_file_it_would_print_and_changes_nothing
    open_intent
    index_with_cluster
    before = File.read(index_path)
    result = cli("sync", "up", "--dry-run")

    assert_equal [0, true, before], [result.code, result.out.include?("paths that would change: 1"), File.read(index_path)], result.err
  end

  def test_sync_up_leaves_a_re_indented_index_alone
    open_intent
    compact = JSON.generate(JSON.parse(File.read(index_path)))
    write("store/index.json", compact)
    result = cli("sync", "up")

    assert_equal [0, compact], [result.code, File.read(index_path)], result.err
  end

  def test_sync_up_names_the_overwrite_that_clears_a_file_it_cannot_read
    specified
    other = open_intent("Beta")
    write("#{other.dir}/graph.json", "{\"hand\":true}\n")
    result = cli("sync", "up")

    assert_equal [1, true], [result.code, result.out.include?("sync down --overwrite #{other.dir}/graph.json")], result.err
  end

  # A preview copies committed files, so it runs in a home of its own: the dry run, the file it left, then the real run.
  def preview_then_apply(path, text)
    with_home do |home|
      yield home
      file = File.join(home, "stores", "global", path)
      File.write(file, text)
      [call_in(home, "sync", "up", "--dry-run"), File.read(file), call_in(home, "sync", "up")]
    end
  end

  def test_a_preview_of_sync_up_names_a_file_it_cannot_read_and_exits_as_the_real_run_does
    path = "store/1--beta/graph.json"
    dry, kept, real = preview_then_apply(path, "{\"hand\":true}\n") { |home| call_in(home, "intent", "new", "Beta") }

    assert_equal [1, true, "{\"hand\":true}\n", 1], [dry.code, dry.err.include?("sync down --overwrite #{path}"), kept, real.code], dry.out + dry.err
  end

  def test_a_preview_of_sync_up_names_a_changed_roadmap_it_cannot_read_and_exits_as_the_real_run_does
    path = "roadmaps/r1.md"
    dry, kept, real = preview_then_apply(path, "# by hand\n") { |home| call_in(home, "roadmap", "new", "r1") }

    assert_equal [1, true, "# by hand\n", 1], [dry.code, dry.err.include?("sync down --overwrite #{path}"), kept, real.code], dry.out + dry.err
  end

  def conflicting_spec(home)
    call_in(home, "intent", "new", "Beta")
    spec = File.join(home, "stores", "global", "store/1--beta/spec.md")
    File.write(spec, "# Spec\n\n## Done criteria\n- [ ] [done] it is done\n")
    call_in(home, "sync", "up")
    home_graphs(home).databases[:knowledge].transaction { |batch| batch.put(:documents, { intent_id: "1", path: "spec.md", body: "row change", updated_at: STAMP }) }
    File.write(spec, "file change\n")
  end

  def test_a_preview_of_sync_up_refuses_a_conflict_as_the_real_run_does_also_with_merge
    codes = [[], ["--merge"]].flat_map do |options|
      with_home do |home|
        conflicting_spec(home)
        [call_in(home, "sync", "up", "--dry-run", *options).code, call_in(home, "sync", "up", *options).code]
      end
    end

    assert_equal [3, 3, 3, 3], codes
  end

  def test_a_preview_of_sync_up_with_an_overwrite_that_names_no_file_prints_the_plain_reason
    dry = with_home { |home| call_in(home, "sync", "up", "--dry-run", "--overwrite", "store/9--none/spec.md") }

    assert_equal [1, "plastic: store/9--none/spec.md names no file and no rows of this store\n"], [dry.code, dry.err], dry.out
  end
end

# Sync up reads the notes and the graph of an intent always, and its other files only as the settings ask.
class SyncUpSelectionTest < Plastic::TestCase
  def sync = plastic("sync", "up", table: Plastic::CLI::TABLE)

  def setup
    super
    page = "---\nid: \"2\"\nintent: \"Beta\"\ncreated: #{STAMP.to_json}\n---\n\n# 2 - Beta\n"
    { "2--beta.md" => page, "spec.md" => "# Spec\n", "resources/shot.png" => "\x89PNG\x00".b,
      "resources/page.html" => "<p>page</p>\n", "references/notes.md" => "# Notes\n" }
      .each { |rel, bytes| write("store/2--beta/#{rel}", bytes) }
  end

  def kept = store_graphs.databases[:references].rows("SELECT name FROM sqlar ORDER BY name").map { |row| row["name"] }

  def documents = store_graphs.databases[:knowledge].rows("SELECT path FROM documents ORDER BY path").map { |row| row["path"] }

  def test_a_sync_with_no_setting_reads_the_notes_and_leaves_the_other_files_on_disk
    result = sync

    assert_equal [0, ""], [result.code, result.err]
    assert_equal [%w[2--beta.md spec.md], []], [documents, kept]
    assert_path_exists folder.path("store/2--beta/references/notes.md")
  end

  def test_a_sync_with_the_media_setting_on_keeps_the_image_and_no_other_file
    File.write(File.join(@plastic_home, "config.yml"), "global:\n  sync:\n    media: true\n")

    assert_equal 0, sync.code
    assert_equal [%w[2--beta.md spec.md], %w[store/2--beta/resources/shot.png]], [documents, kept]
  end

  def test_a_kept_image_is_not_read_again_once_the_media_setting_is_off
    config = File.join(@plastic_home, "config.yml")
    File.write(config, "global:\n  sync:\n    media: true\n")
    sync
    File.write(config, "global:\n  sync:\n    media: false\n")
    write("store/2--beta/resources/shot.png", "\x89PNG\x00 changed".b)
    result = sync

    assert_equal [0, ""], [result.code, result.err]
    assert_equal [5], store_graphs.databases[:references].rows("SELECT sz FROM sqlar").map { |row| row["sz"] }
  end
end

class SyncUpGraphArchiveKeptTest < Minitest::Test
  include DeliveredHomes

  def kept(kernel)
    kernel.command!("intent", "new", "Waiting", "--status", "parked", "--reason", "Waiting for the supplier")
    kernel.command!("intent", "new", "Dropped")
    abandon(kernel, "3")
  end

  def test_a_parked_and_an_abandoned_intent_keep_their_reason_and_disposition_on_a_second_home
    with_homes(method(:kept)) do |first, second|
      second.command!("sync", "up")
      sql = "SELECT intent_id, status, disposition, reason FROM intents ORDER BY intent_id"

      assert_includes query(second, sql), ["2", "parked", nil, "Waiting for the supplier"]
      assert_equal query(first, sql), query(second, sql)
    end
  end
end

class SyncUpGraphArchiveRefusalTest < Minitest::Test
  include DeliveredHomes

  def archived(kernel)
    deliver(kernel)
    kernel.command!("intent", "archive", "1")
  end

  def test_unarchive_on_the_second_home_refuses_and_leaves_the_archive_mark
    with_homes(method(:archived)) do |_first, second|
      second.command!("sync", "up")
      call = second.command("intent", "unarchive", "1")

      assert_equal [1, [[nil]], false], [call.code, query(second, "SELECT restored_at FROM archives"), File.exist?(second.path(DIR))]
      assert_match(/snapshot is on the first home/, call.reason)
    end
  end
end

class SyncUpGraphArchiveRepeatTest < Minitest::Test
  include DeliveredHomes

  ARCHIVES = "SELECT intent_id, at, session_id, restored_at FROM archives"
  COMPLETION = "SELECT intent_id, at, session_id, judge, criteria, evidence, outcome_sha256 FROM completions"

  def archived(kernel)
    deliver(kernel)
    kernel.command!("intent", "archive", "1")
  end

  def rows_of(home) = [query(home, ARCHIVES), query(home, COMPLETION)]

  def test_a_delivered_archived_intent_arrives_with_its_completion_and_a_second_sync_up_changes_nothing
    with_homes(method(:archived)) do |first, second|
      second.command!("sync", "up")
      arrived = rows_of(second)
      index = second.read("store/index.json")

      refute_empty arrived.last
      assert_equal rows_of(first), arrived

      second.command!("sync", "up")

      assert_equal [arrived, index], [rows_of(second), second.read("store/index.json")]
    end
  end
end

class SyncUpGraphArchiveRestoredTest < Minitest::Test
  include DeliveredHomes

  ARCHIVES = "SELECT intent_id, at, session_id, restored_at FROM archives"

  def archived(kernel)
    deliver(kernel)
    kernel.command!("intent", "archive", "1")
  end

  def test_a_restored_archive_survives_a_sync_up
    with_homes(method(:archived)) do |first, second|
      second.command!("sync", "up")
      first.command!("intent", "unarchive", "1")
      before = query(first, ARCHIVES)
      first.command!("sync", "up")

      assert_equal before, query(first, ARCHIVES)
      refute_nil before.first.last
    end
  end
end

class SyncUpGraphArchiveTest < Minitest::Test
  include DeliveredHomes

  COMPLETION = "SELECT intent_id, at, session_id, judge, criteria, evidence, outcome_sha256 FROM completions"
  ARCHIVES = "SELECT intent_id, at, session_id, restored_at FROM archives"

  def archived(kernel)
    kernel.write("#{DIR}/outcome.md", DROPPED)
    kernel.command!("sync", "up")
    kernel.command!("intent", "abandon", "1", env: SESSION)
    kernel.command!("intent", "archive", "1")
  end

  def seen_from(home) = [query(home, ARCHIVES), query(home, "SELECT status, disposition FROM intents"), query(home, COMPLETION), unstamped(home.read("store/index.json"))]

  def test_an_archived_intent_reads_archived_with_its_status_completion_and_index_on_a_second_home
    with_homes(method(:archived)) do |first, second|
      second.command!("sync", "up")

      assert_equal seen_from(first), seen_from(second)
      assert_equal [["1", nil]], query(second, "SELECT intent_id, restored_at FROM archives")
    end
  end
end

class SyncUpGraphClaimTest < Minitest::Test
  include TwoHomes

  def test_the_second_home_can_claim_the_next_node_of_the_graph
    with_two_homes do |_first, second|
      second.command!("sync", "up")

      assert_includes second.command!("node", "claim", "1", "n2").out, "n2"
    end
  end
end

class SyncUpGraphCompletionFileTest < Minitest::Test
  include DeliveredHomes

  def test_the_graph_file_of_a_delivered_intent_holds_the_completion
    with_homes(method(:deliver)) do |first, _second|
      completion = JSON.parse(first.read(GRAPH)).fetch("completion")

      assert_equal "verdict", completion.fetch("judge")
    end
  end
end

class SyncUpGraphCompletionStatusTest < Minitest::Test
  include DeliveredHomes

  def test_a_delivered_intent_reads_done_and_delivered_on_a_second_home
    with_homes(method(:deliver)) do |_first, second|
      second.command!("sync", "up")

      assert_equal [["done", "delivered"]], query(second, "SELECT status, disposition FROM intents")
    end
  end
end

class SyncUpGraphCompletionTest < Minitest::Test
  include DeliveredHomes

  COMPLETION = "SELECT intent_id, at, session_id, judge, criteria, evidence, outcome_sha256 FROM completions"

  def test_the_completion_of_a_delivered_intent_continues_on_a_second_home
    with_homes(method(:deliver)) do |first, second|
      second.command!("sync", "up")

      refute_empty query(first, COMPLETION)
      assert_equal query(first, COMPLETION), query(second, COMPLETION)
      assert_equal [second.origin], query(second, "SELECT origin_id FROM completions").flatten
    end
  end
end

class SyncUpGraphDownTest < Minitest::Test
  include TwoHomes

  def test_sync_down_after_the_move_writes_nothing_and_exits_zero
    with_two_homes do |first, second|
      second.command!("sync", "up")
      call = second.command("sync", "down")

      assert_equal [0, "none"], [call.code, call.files]
      assert_equal first.read(GRAPH), second.read(GRAPH)
    end
  end
end

class SyncUpGraphEmptiedTest < Minitest::Test
  include TwoHomes

  def test_a_graph_emptied_in_one_home_is_read_in_the_other_and_empties_the_rows_there
    with_two_homes do |first, second|
      second.command!("sync", "up")
      emptied = JSON.pretty_generate(JSON.parse(second.read(GRAPH)).merge("approval" => nil, "verdicts" => [], "nodes" => [], "edges" => []))
      second.write(GRAPH, "#{emptied}\n")
      second.command!("sync", "up")
      first.write(GRAPH, second.read(GRAPH))
      first.command!("sync", "up")

      assert_equal [[], []], [query(second, "SELECT id FROM nodes"), query(first, "SELECT id FROM nodes")]
    end
  end
end

class SyncUpGraphIndexTest < Minitest::Test
  include TwoHomes

  def test_the_index_after_the_move_equals_the_copied_one_except_for_origin_ids
    with_two_homes do |first, second|
      copied = unstamped(second.read("store/index.json"))
      second.command!("sync", "up")

      assert_equal copied, unstamped(second.read("store/index.json"))
      assert_equal unstamped(first.read("store/index.json")), unstamped(second.read("store/index.json"))
    end
  end

  def test_a_verdict_survives_the_move
    with_two_homes do |first, second|
      second.command!("sync", "up")
      sql = "SELECT round, verdict, findings FROM verdicts"

      refute_empty query(first, sql)
      assert_equal query(first, sql), query(second, sql)
    end
  end
end

class SyncUpGraphRepeatTest < Minitest::Test
  include TwoHomes

  def test_a_second_sync_up_leaves_graph_json_and_its_printed_hash_as_they_are
    with_two_homes do |first, second|
      second.command!("sync", "up")
      bytes = second.read(GRAPH)
      printed = second.rows("work_graph.db", "SELECT sha256 FROM printed WHERE path = '#{GRAPH}'")
      second.command!("sync", "up")

      assert_equal bytes, first.read(GRAPH)
      assert_equal [bytes, printed], [second.read(GRAPH), second.rows("work_graph.db", "SELECT sha256 FROM printed WHERE path = '#{GRAPH}'")]
    end
  end
end

class SyncUpGraphSurvivalTest < Minitest::Test
  include TwoHomes

  def test_findings_that_hold_id_and_intent_id_survive_the_move_unchanged
    with_two_homes do |_first, second|
      second.command!("sync", "up")

      assert_equal ["The test is red for the right reason; see :id and :intent_id"], query(second, "SELECT findings FROM nodes WHERE id = 'n1'").flatten
    end
  end
end

class SyncUpGraphTest < Minitest::Test
  include TwoHomes

  def test_the_nodes_of_one_machine_continue_on_a_second_home_after_sync_up
    with_two_homes do |first, second|
      second.command!("sync", "up")

      assert_equal nodes(first), nodes(second)
      assert_equal [second.origin], query(second, "SELECT DISTINCT origin_id FROM nodes").flatten
    end
  end

  def test_the_edges_approval_and_status_of_one_machine_continue_on_a_second_home
    with_two_homes do |first, second|
      second.command!("sync", "up")
      sql = ["SELECT count(*) FROM edges", "SELECT count(*) FROM approvals", "SELECT status FROM intents"]

      assert_equal sql.map { |text| query(first, text) }, sql.map { |text| query(second, text) }
    end
  end
end

class SyncUpGraphViewsTest < Minitest::Test
  include TwoHomes

  def test_graph_show_and_graph_resume_say_the_same_in_both_homes
    with_two_homes do |first, second|
      second.command!("sync", "up")

      assert_equal first.command!("graph", "show", "1").out, second.command!("graph", "show", "1").out
      assert_equal first.command!("graph", "resume").out, second.command!("graph", "resume").out
    end
  end
end

# What the first sync of a legacy store removes, when the config asks it to.
class SyncLegacyCleanupTest < Plastic::TestCase
  fixtures :legacy

  def apply = plastic("sync", "up", table: Plastic::CLI::TABLE)

  def remove_after_import = File.write(File.join(@plastic_home, "config.yml"), "migrate:\n  remove_after_import: true\n")

  def test_the_import_keeps_index_md
    apply

    assert folder.exist?("INDEX.md")
  end

  def test_index_md_goes_after_the_import_when_the_flag_is_on
    remove_after_import

    apply

    refute folder.exist?("INDEX.md")
    assert_equal %w[1 1a], retrieval.intents.map(&:intent_id).sort
  end

  def test_a_completed_intent_is_archived_when_the_flag_is_on
    write("store/2--lone/2--lone.md", "---\nid: \"2\"\nintent: \"Stand alone\"\n---\n\n## Intent\nStand alone\n")
    write("INDEX.md", folder.read("INDEX.md").sub("## Completed\n", "## Completed\n- [2 - Stand alone](store/2--lone/2--lone.md)\n"))
    remove_after_import

    call = apply

    assert_includes call.out, "1 archived"
  end

  def test_regular_sync_keeps_source_files_after_import
    apply
    remove_after_import

    apply

    assert folder.exist?("INDEX.md")
  end
end

class SyncLegacyMetadataTest < Plastic::TestCase
  fixtures :legacy

  ROADMAP = <<~MARKDOWN
    # Ship the client

    ## Batches

    - [x] 1 Build alpha — delivered
    - [ ] 1a Deploy the gateway — queued
  MARKDOWN

  def apply = plastic("sync", "up", table: Plastic::CLI::TABLE)

  def spec_with(decisions) = "# Spec\n\n## Decisions\n#{decisions.map { |line| "- #{line}\n" }.join}"

  def test_colliding_ruling_ids_take_the_next_free_number
    write("store/1--alpha-service/spec.md", spec_with(["D1 Use a shared server", "D1 Use one gateway", "Keep it local"]))

    apply

    assert_equal %w[D1 D2 D3], retrieval.rulings("1").map(&:id)
  end

  def test_spec_decisions_win_over_the_intent_file
    write("store/1--alpha-service/spec.md", spec_with(["D1 Use a shared server"]))
    write("store/1--alpha-service/1--alpha-service.md", "#{folder.read("store/1--alpha-service/1--alpha-service.md")}\n## Decisions\n- D1 Use shared servers\n")

    apply

    assert_equal ["D1 Use a shared server"], retrieval.rulings("1").map(&:text)
  end

  def test_a_roadmap_with_no_batch_heading_lands_in_batch_one
    write("roadmaps/ship.md", ROADMAP)

    apply

    assert_equal [[1, "Ship the client"]], retrieval.batches("ship").map { |batch| [batch.position, batch.title] }
    assert_equal [1, 1], retrieval.roadmap_items("ship").map(&:batch)
  end

  def test_an_imported_item_names_the_intent_with_its_id
    write("roadmaps/ship.md", ROADMAP)

    apply

    assert_equal %w[1 1a], retrieval.roadmap_items("ship").map(&:intent_id)
  end

  def test_savepoint_lines_join_the_roadmap_log
    write("roadmaps/ship.md", ROADMAP)
    write("roadmaps/ship.savepoint.md", "2026-09-01T10:00:00+02:00 Batch 1 opened\n")

    apply

    assert_equal ["Batch 1 opened"], retrieval.roadmap_log("ship").map(&:text)
    assert_nil retrieval.roadmap("ship.savepoint")
  end

  def test_a_second_apply_says_no_store_is_left
    apply

    assert_equal 0, apply.code
  end

  def test_a_batch_with_no_goal_prints_without_a_dash
    write("roadmaps/ship.md", ROADMAP)
    apply

    result = plastic("roadmap", "show", "ship", table: Plastic::CLI::TABLE)

    assert_includes result.out, "batch 1: Ship the client\n"
    assert_equal 0, result.code
    assert_equal "", result.err
  end

  def test_a_roadmap_title_loses_its_roadmap_prefix
    write("roadmaps/ship.md", ROADMAP.sub("# Ship", "# Roadmap: Ship"))

    apply

    assert_equal "Ship the client", retrieval.roadmap("ship").title
  end

  def test_waits_read_in_number_order
    write("roadmaps/ship.md", "# Ship\n\n## Batches\n\n- [ ] 9 A — queued\n- [ ] 10 B — queued\n- [ ] 11 C — queued\n\n" \
                              "## Graph\n\n- 9 needs nothing\n- 10 needs nothing\n- 11 needs 10 9\n")
    apply

    assert_equal %w[9 10], retrieval.roadmap_edges("ship").map(&:from)
  end

  def test_a_store_that_fails_halfway_gets_its_folder_back
    Dir.mktmpdir do |dir|
      root = File.join(dir, "store-a")
      FileUtils.mkdir_p(root)
      File.write(File.join(root, "INDEX.md"), "before")
      rollback = Plastic::Graph::Knowledge::Legacy::ImportRollback.new(root)

      assert_raises(RuntimeError) { rollback.call { File.write(File.join(root, "work_graph.db"), "x") && raise("halfway") } }
      assert_equal ["INDEX.md"], Dir.children(root)
    end
  end

  def test_a_roadmap_line_it_cannot_read_refuses_the_import
    write("roadmaps/ship.md", "# Ship\n\n## Batches\n\n- [ ] 9 A\n")

    call = apply

    assert_equal 1, call.code
    assert_includes call.err, "no status on roadmap item"
  end

  def test_an_unknown_roadmap_is_refused
    call = plastic("roadmap", "show", "nosuch", table: Plastic::CLI::TABLE)

    assert_call call, code: 1, out: "", err: "plastic: no roadmap nosuch\n"
  end
end
