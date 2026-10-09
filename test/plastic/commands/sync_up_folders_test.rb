# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/sync_up"

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
    source = Plastic::Graph.open(home: @plastic_home, store: "src")
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

  def test_a_printed_context_json_with_no_row_is_not_imported_as_a_document
    hand_folder("2", "beta", "Beta")
    write("store/2--beta/context.json", JSON.generate("intent" => "2", "context" => { "forged" => true }))
    sync

    assert_equal 0, store_graphs.databases[:knowledge].rows("SELECT * FROM documents WHERE path = 'context.json'").size
    assert_empty store_graphs.databases[:knowledge].rows("SELECT * FROM retrieval_contexts")
  end
end
