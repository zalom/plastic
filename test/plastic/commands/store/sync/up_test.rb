# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/commands/store/sync/up"
require "json"
require_relative "../../../../test_helpers/delivered_homes"
require_relative "../../../../test_helpers/two_homes"

class SyncUpTest < Plastic::TestCase
  fixtures :legacy

  def import = plastic("store", "sync", "up", table: Plastic::CLI::TABLE)

  def legacy_metadata
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

  def test_sync_up_wrote_line_names_the_rows_and_leaves_out_the_command_run
    result = import

    assert_includes result.out, "wrote:  2 work log lines in work_graph.db"
    assert_includes result.out.squeeze(" "), "2 intents, 6 documents, 6 document heads, and 6 legacy files in knowledge_graph.db"
    refute_includes result.out, "command run"
  end

  def test_preview_does_not_import_the_original_store
    before = snapshot(store_root)
    result = plastic("store", "sync", "up", "--dry-run", table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: ["preview"]
    assert_equal before, snapshot(store_root)
  end
end

# Sync up reads every intent folder, whatever store/index.json says.
class SyncUpFoldersTest < Plastic::TestCase
  def sync = plastic("store", "sync", "up", table: Plastic::CLI::TABLE)

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

  def intent_ids = retrieval.intents.map(&:intent_id)

  def index_ids = JSON.parse(folder.read("store/index.json"))["intents"].map { |entry| entry["intent_id"] }

  def document_bodies(intent_id)
    store_graphs.databases.fetch(:store).rows("SELECT body FROM documents WHERE intent_id = '#{intent_id}' AND path = 'spec.md'")
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

    assert_equal [0, 1], [store_graphs.databases.fetch(:store).rows("SELECT * FROM documents WHERE path = 'context.json'").size,
      store_graphs.databases.fetch(:store).rows("SELECT * FROM retrieval_contexts").size]
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
    result = cli("store", "sync", "up")

    assert_equal [0, "{}\n"], [result.code, File.read(store_path(path))], result.err
  end

  def test_sync_up_prints_a_generated_index_with_other_content_and_leaves_it_level
    open_intent
    index_with_cluster
    result = cli("store", "sync", "up")
    printed = File.read(index_path)

    assert_equal [0, "#{JSON.pretty_generate(JSON.parse(printed))}\n", true], [result.code, printed, printed.include?("imported")], result.err
  end

  def test_a_preview_of_sync_up_counts_the_generated_file_it_would_print_and_changes_nothing
    open_intent
    index_with_cluster
    before = File.read(index_path)
    result = cli("store", "sync", "up", "--dry-run")

    assert_equal [0, true, before], [result.code, result.out.include?("paths that would change: 1"), File.read(index_path)], result.err
  end

  def test_sync_up_leaves_a_re_indented_index_alone
    open_intent
    compact = JSON.generate(JSON.parse(File.read(index_path)))
    write("store/index.json", compact)
    result = cli("store", "sync", "up")

    assert_equal [0, compact], [result.code, File.read(index_path)], result.err
  end

  def test_sync_up_names_the_overwrite_that_clears_a_file_it_cannot_read
    specified
    other = open_intent("Beta")
    write("#{other.dir}/graph.json", "{\"hand\":true}\n")
    result = cli("store", "sync", "up")

    assert_equal [1, true], [result.code, result.out.include?("sync down --overwrite #{other.dir}/graph.json")], result.err
  end

  def test_sync_up_fails_on_a_hand_edit_of_a_closed_intents_spec_and_offers_the_overwrite
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped.\n\n## Verification\n- Abandoned: dropped because the need went away\n")
    cli("store", "sync", "up")
    cli("intent", "abandon", "1")
    write("#{intent.dir}/spec.md", "# Spec\n\nRewritten after the close.\n")
    result = cli("store", "sync", "up")
    printed = "#{intent.dir}/spec.md: intent 1 is abandoned, and a closed intent keeps its spec.md as it closed; " \
      "run plastic store sync down --overwrite #{intent.dir}/spec.md"

    assert_equal [1, true, false], [result.code, result.out.include?(printed), retrieval.fetch("1", "spec.md").body.include?("Rewritten")], result.err
  end

  # A preview copies committed files, so it runs in a home of its own: the dry run, the file it left, then the real run.
  def preview_then_apply(path, text)
    with_home do |home|
      yield home
      file = File.join(home, "stores", "global", path)
      File.write(file, text)
      [call_in(home, "store", "sync", "up", "--dry-run"), File.read(file), call_in(home, "store", "sync", "up")]
    end
  end

  def test_a_preview_of_sync_up_names_a_file_it_cannot_read_and_exits_as_the_real_run_does
    path = "store/1--beta/graph.json"
    dry, kept, real = preview_then_apply(path, "{\"hand\":true}\n") { |home| call_in(home, "intent", "new", "Beta") }

    assert_equal [1, true, "{\"hand\":true}\n", 1], [dry.code, dry.err.include?("sync down --overwrite #{path}"), kept, real.code], dry.out + dry.err
  end

  def conflicting_spec(home)
    call_in(home, "intent", "new", "Beta")
    spec = File.join(home, "stores", "global", "store/1--beta/spec.md")
    File.write(spec, "# Spec\n\n## Done criteria\n- [ ] [done] it is done\n")
    call_in(home, "store", "sync", "up")
    home_graphs(home).databases.fetch(:store).transaction { |batch| batch.put(:documents, { intent_id: "1", path: "spec.md", body: "row change", updated_at: STAMP }) }
    File.write(spec, "file change\n")
  end

  def test_a_preview_of_sync_up_refuses_a_conflict_as_the_real_run_does_also_with_merge
    codes = [[], ["--merge"]].flat_map do |options|
      with_home do |home|
        conflicting_spec(home)
        [call_in(home, "store", "sync", "up", "--dry-run", *options).code, call_in(home, "store", "sync", "up", *options).code]
      end
    end

    assert_equal [3, 3, 3, 3], codes
  end

  def test_a_preview_of_sync_up_with_an_overwrite_that_names_no_file_prints_the_plain_reason
    dry = with_home { |home| call_in(home, "store", "sync", "up", "--dry-run", "--overwrite", "store/9--none/spec.md") }

    assert_equal [1, "plastic: store/9--none/spec.md names no file and no rows of this store\n"], [dry.code, dry.err], dry.out
  end
end

# An intent folder, 2--beta, with one file of each kind, and the sync up and the rows read over it.
module BetaFolder
  include ConfigHomes

  def sync = plastic("store", "sync", "up", table: Plastic::CLI::TABLE)

  def setup
    super
    page = "---\nid: \"2\"\nintent: \"Beta\"\ncreated: #{Plastic::TestCase::STAMP.to_json}\n---\n\n# 2 - Beta\n"
    { "2--beta.md" => page, "spec.md" => "# Spec\n", "resources/output/files/shot.png" => "\x89PNG\x00".b,
      "resources/output/reports/page.html" => "<p>page</p>\n", "resources/references/notes.md" => "# Notes\n",
      "resources/tmp/scratch.md" => "# Scratch\n" }
      .each { |rel, bytes| write("store/2--beta/#{rel}", bytes) }
  end

  def kept = store_graphs.databases.fetch(:store).rows("SELECT name FROM sqlar ORDER BY name").map { |row| row["name"] }

  def documents = store_graphs.databases.fetch(:store).rows("SELECT path FROM documents ORDER BY path").map { |row| row["path"] }

  def record_report(rel)
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.put(:work_log, { intent_id: "2", position: 1, at: Plastic::TestCase::STAMP, phase: "", node: "", session_id: "s", kind: "reported", path: rel, sha256: "", text: "the page" })
    end
  end
end

# Sync up reads the notes and the graph of an intent always, and its other files only as the settings ask.
class SyncUpSelectionTest < Plastic::TestCase
  include BetaFolder

  def asked = Plastic::Wiring.config(@plastic_home).list("sync.asked")

  def test_a_sync_with_no_setting_reads_the_notes_and_leaves_the_other_files_on_disk
    result = sync

    assert_equal [0, ""], [result.code, result.err]
    assert_equal [%w[2--beta.md spec.md], []], [documents, kept]
    assert_path_exists folder.path("store/2--beta/resources/references/notes.md")
  end

  def test_an_unrecorded_report_stays_on_disk_with_no_row
    sync

    assert_equal [false, true], [documents.include?("resources/output/reports/page.html"), File.file?(folder.path("store/2--beta/resources/output/reports/page.html"))]
  end

  def test_a_recorded_report_is_read
    sync
    record_report("resources/output/reports/page.html")
    sync

    assert_includes documents, "resources/output/reports/page.html"
  end

  def test_a_mandatory_report_is_read_with_no_record
    seed_config(@plastic_home, "global:\n  reports:\n    mandatory: [page.html]\n")
    sync

    assert_includes documents, "resources/output/reports/page.html"
  end

  def test_a_sync_with_the_png_type_included_keeps_the_image_and_no_other_file
    seed_config(@plastic_home, "global:\n  sync:\n    types: [md, html, png]\n")

    assert_equal 0, sync.code
    assert_equal [%w[2--beta.md spec.md], %w[store/2--beta/resources/output/files/shot.png]], [documents, kept]
  end

  def test_a_sync_with_the_references_setting_on_reads_the_references_and_never_the_tmp_folder
    seed_config(@plastic_home, "global:\n  sync:\n    references: true\n")

    assert_equal 0, sync.code
    assert_equal %w[2--beta.md resources/references/notes.md spec.md], documents
  end

  def types(value) = seed_config(@plastic_home, "global:\n  sync:\n    types: #{value}\n")

  def kept_sizes = store_graphs.databases.fetch(:store).rows("SELECT sz FROM sqlar").map { |row| row["sz"] }

  def test_a_kept_image_is_not_read_again_once_the_type_is_left_out
    types("[md, html, png]")
    sync
    types("[md, html]")
    write("store/2--beta/resources/output/files/shot.png", "\x89PNG\x00 changed".b)
    result = sync

    assert_equal [0, "", [5]], [result.code, result.err, kept_sizes]
  end

  def test_a_new_type_prints_one_line_naming_the_config_command
    result = sync

    assert_includes result.out, "files of type .png are not synced; run plastic config set sync.types md,html,png to include them"
  end

  def test_the_line_is_printed_once_per_type
    sync

    assert_equal [%w[png], false], [asked, sync.out.include?("files of type .png")]
  end

  def test_a_type_already_included_prints_no_line
    types("[md, html, png]")

    refute_includes sync.out, "files of type"
  end

  def test_the_sync_succeeds_when_the_asked_setting_cannot_be_written
    File.write(File.join(@plastic_home, "config.yml"), "edited by hand\n")
    result = sync

    assert_equal 0, result.code
  end
end

# A sync up removes the rows of a path it no longer reads, here a report whose record went.
class SyncUpUnreadRowsTest < Plastic::TestCase
  include BetaFolder

  PAGE = "resources/output/reports/page.html"

  def left_the_selection
    record_report(PAGE)
    sync
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("DELETE FROM work_log WHERE kind = :kind", kind: "reported") }
  end

  def row_count(sql) = store_graphs.databases.fetch(:store).rows(sql, path: PAGE, printed: "store/2--beta/#{PAGE}").first.values.first

  def rows_of_the_page
    ["SELECT count(*) FROM main.documents WHERE path = :path", "SELECT count(*) FROM main.document_heads WHERE path = :path",
      "SELECT count(*) FROM main.printed WHERE path = :printed", "SELECT count(*) FROM retrieval.document_passages WHERE path = :path",
      "SELECT count(*) FROM retrieval.document_fts WHERE path = :path"].map { |sql| row_count(sql) }
  end

  # The dry run prints the lines of this same plan, applied to its copy of the store.
  def test_the_plan_counts_and_names_the_rows_of_a_path_the_sync_no_longer_reads
    left_the_selection
    work = store_graphs.work
    plan = work.sync_plan(:up, {})

    assert_equal [1, ["removed the rows of store/2--beta/#{PAGE}: the sync no longer reads it"]],
      [plan.pending, work.sync_apply(plan).grep(/removed the rows/)]
  end

  def test_a_sync_up_removes_every_row_of_a_path_the_sync_no_longer_reads
    left_the_selection
    store_graphs.retrieval.reindex
    before = rows_of_the_page.map(&:positive?)
    sync

    assert_equal [[true] * 5, [0] * 5, true], [before, rows_of_the_page, File.file?(folder.path("store/2--beta/#{PAGE}"))]
  end

  def test_a_sync_down_after_the_removal_prints_nothing_at_that_path
    left_the_selection
    sync
    File.delete(folder.path("store/2--beta/#{PAGE}"))
    plastic("store", "sync", "down", table: Plastic::CLI::TABLE)

    refute_path_exists folder.path("store/2--beta/#{PAGE}")
  end
end

# A sync up rebuilds the search rows of what it read, so a search finds it with no sync down and no doctor run.
class SyncUpSearchTest < Plastic::TestCase
  include BetaFolder

  def found(words)
    result = plastic("search", words, "--json", table: Plastic::CLI::TABLE)
    JSON.parse(result.out).fetch("result").fetch("rows").map { |row| row.fetch("uri")[%r{\Aplastic://global/2/([^?]+)}, 1] }
  end

  def test_a_search_finds_a_new_file_right_after_the_sync_up
    sync
    write("store/2--beta/resources/output/files/findings.md", "# Findings\n\nThe zanzibar route is the fastest.\n")
    sync

    assert_equal ["resources%2Foutput%2Ffiles%2Ffindings.md"], found("zanzibar")
  end

  def test_a_search_finds_the_new_words_of_a_changed_file_and_not_the_old_ones
    write("store/2--beta/spec.md", "# Spec\n\nThe zanzibar plan.\n")
    sync
    write("store/2--beta/spec.md", "# Spec\n\nThe kilimanjaro plan.\n")
    sync

    assert_equal [["spec.md"], []], [found("kilimanjaro"), found("zanzibar")]
  end
end

class SyncUpGraphArchiveKeptTest < Minitest::Test
  include DeliveredHomes

  def kept(kernel)
    kernel.command!("intent", "new", "Waiting")
    kernel.command!("intent", "start", "2", env: SESSION)
    kernel.command!("intent", "park", "2", "Waiting", "for", "the", "supplier", env: SESSION)
    kernel.command!("intent", "new", "Dropped")
    abandon(kernel, "3")
  end

  def test_a_parked_and_an_abandoned_intent_keep_their_reason_and_disposition_on_a_second_home
    with_homes(method(:kept)) do |first, second|
      second.command!("store", "sync", "up")
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
      second.command!("store", "sync", "up")
      call = second.command("intent", "unarchive", "1")

      assert_equal [3, [[nil]], false], [call.code, query(second, "SELECT restored_at FROM archives"), File.exist?(second.path(DIR))]
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
      second.command!("store", "sync", "up")
      arrived = rows_of(second)
      index = second.read("store/index.json")

      refute_empty arrived.last
      assert_equal rows_of(first), arrived

      second.command!("store", "sync", "up")

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
      second.command!("store", "sync", "up")
      first.command!("intent", "unarchive", "1")
      before = query(first, ARCHIVES)
      first.command!("store", "sync", "up")

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
    kernel.command!("store", "sync", "up")
    kernel.command!("intent", "abandon", "1", env: SESSION)
    kernel.command!("intent", "archive", "1")
  end

  def seen_from(home) = [query(home, ARCHIVES), query(home, "SELECT status, disposition FROM intents"), query(home, COMPLETION), unstamped(home.read("store/index.json"))]

  def test_an_archived_intent_reads_archived_with_its_status_completion_and_index_on_a_second_home
    with_homes(method(:archived)) do |first, second|
      second.command!("store", "sync", "up")

      assert_equal seen_from(first), seen_from(second)
      assert_equal [["1", nil]], query(second, "SELECT intent_id, restored_at FROM archives")
    end
  end
end

class SyncUpGraphClaimTest < Minitest::Test
  include TwoHomes

  def test_the_second_home_can_claim_the_next_node_of_the_graph
    with_two_homes do |_first, second|
      second.command!("store", "sync", "up")

      assert_includes second.command!("node", "claim", "1", "n2", "--agent", "tester").out, "n2"
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
      second.command!("store", "sync", "up")

      assert_equal [["done", "delivered"]], query(second, "SELECT status, disposition FROM intents")
    end
  end
end

class SyncUpGraphCompletionTest < Minitest::Test
  include DeliveredHomes

  COMPLETION = "SELECT intent_id, at, session_id, judge, criteria, evidence, outcome_sha256 FROM completions"

  def test_the_completion_of_a_delivered_intent_continues_on_a_second_home
    with_homes(method(:deliver)) do |first, second|
      second.command!("store", "sync", "up")

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
      second.command!("store", "sync", "up")
      call = second.command("store", "sync", "down")

      assert_equal [0, "none"], [call.code, call.files]
      assert_equal first.read(GRAPH), second.read(GRAPH)
    end
  end
end

class SyncUpGraphEmptiedTest < Minitest::Test
  include TwoHomes

  def test_a_graph_emptied_in_one_home_is_read_in_the_other_and_empties_the_rows_there
    with_two_homes do |first, second|
      second.command!("store", "sync", "up")
      emptied = JSON.pretty_generate(JSON.parse(second.read(GRAPH)).merge("approval" => nil, "verdicts" => [], "nodes" => [], "edges" => []))
      second.write(GRAPH, "#{emptied}\n")
      second.command!("store", "sync", "up")
      first.write(GRAPH, second.read(GRAPH))
      first.command!("store", "sync", "up")

      assert_equal [[], []], [query(second, "SELECT id FROM nodes"), query(first, "SELECT id FROM nodes")]
    end
  end
end

class SyncUpGraphIndexTest < Minitest::Test
  include TwoHomes

  def test_the_index_after_the_move_equals_the_copied_one_except_for_origin_ids
    with_two_homes do |first, second|
      copied = unstamped(second.read("store/index.json"))
      second.command!("store", "sync", "up")

      assert_equal copied, unstamped(second.read("store/index.json"))
      assert_equal unstamped(first.read("store/index.json")), unstamped(second.read("store/index.json"))
    end
  end

  def test_a_verdict_survives_the_move
    with_two_homes do |first, second|
      second.command!("store", "sync", "up")
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
      second.command!("store", "sync", "up")
      bytes = second.read(GRAPH)
      printed = second.rows("knowledge_graph.db", "SELECT sha256 FROM printed WHERE path = '#{GRAPH}'")
      second.command!("store", "sync", "up")

      assert_equal bytes, first.read(GRAPH)
      assert_equal [bytes, printed], [second.read(GRAPH), second.rows("knowledge_graph.db", "SELECT sha256 FROM printed WHERE path = '#{GRAPH}'")]
    end
  end
end

class SyncUpGraphSurvivalTest < Minitest::Test
  include TwoHomes

  def test_findings_that_hold_id_and_intent_id_survive_the_move_unchanged
    with_two_homes do |_first, second|
      second.command!("store", "sync", "up")

      assert_equal ["The test is red for the right reason; see :id and :intent_id"], query(second, "SELECT findings FROM nodes WHERE id = 'n1'").flatten
    end
  end
end

class SyncUpGraphTest < Minitest::Test
  include TwoHomes

  def test_the_nodes_of_one_machine_continue_on_a_second_home_after_sync_up
    with_two_homes do |first, second|
      second.command!("store", "sync", "up")

      assert_equal nodes(first), nodes(second)
      assert_equal [second.origin], query(second, "SELECT DISTINCT origin_id FROM nodes").flatten
    end
  end

  def test_the_edges_approval_and_status_of_one_machine_continue_on_a_second_home
    with_two_homes do |first, second|
      second.command!("store", "sync", "up")
      sql = ["SELECT count(*) FROM edges", "SELECT count(*) FROM approvals", "SELECT status FROM intents"]

      assert_equal sql.map { |text| query(first, text) }, sql.map { |text| query(second, text) }
    end
  end
end

class SyncUpGraphViewsTest < Minitest::Test
  include TwoHomes

  def test_graph_show_and_graph_resume_say_the_same_in_both_homes
    with_two_homes do |first, second|
      second.command!("store", "sync", "up")

      assert_equal first.command!("graph", "show", "1").out, second.command!("graph", "show", "1").out
      assert_equal first.command!("graph", "resume").out, second.command!("graph", "resume").out
    end
  end
end

# What the first sync of a legacy store removes, when the config asks it to.
class SyncLegacyCleanupTest < Plastic::TestCase
  include ConfigHomes

  fixtures :legacy

  def apply = plastic("store", "sync", "up", table: Plastic::CLI::TABLE)

  def remove_after_import = seed_config(@plastic_home, "migrate:\n  remove_after_import: true\n")

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

  def apply = plastic("store", "sync", "up", table: Plastic::CLI::TABLE)

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

  def test_a_second_apply_says_no_store_is_left
    apply

    assert_equal 0, apply.code
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
end

# A sync up reads only the files the layout allows, and names every other file it finds.
class SyncUpStraysTest < Plastic::TestCase
  include BetaFolder

  def test_a_markdown_file_at_the_top_of_a_folder_is_named_and_not_read_as_a_note
    write("store/2--beta/notes.md", "# Notes\n\nThe zanzibar route.\n")
    result = sync

    assert_includes result.out, "store/2--beta/notes.md is not in the intent folder layout; plastic help intent-folder lists the files it allows"
    assert_empty store_graphs.databases.fetch(:store).rows("SELECT path FROM documents WHERE path = 'notes.md'")
  end

  def test_a_file_of_an_older_layout_names_its_repair
    write("store/2--beta/revisions.md", "# Revisions\n")

    assert_includes sync.out, "store/2--beta/revisions.md is a file of an older layout: amend; plastic help intent-folder says why"
  end

  def test_the_files_the_layout_allows_are_not_named
    write("store/2--beta/resources/tmp/scratch.md", "# Scratch\n")
    write("store/2--beta/resources/output/files/shot.png", "png")

    refute_includes sync.out, "is not in the intent folder layout"
  end
end
