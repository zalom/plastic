# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/new"

class IntentNewCaseTest < Plastic::TestCase
  FILES = %w[graph.json intent.md savepoint.md].freeze

  def index_ids
    return [] unless File.exist?(store_path("store/index.json"))

    JSON.parse(File.read(store_path("store/index.json"))).fetch("intents", []).map { |row| row.fetch("intent_id") }
  end

  def files_of(id) = Dir.children(Dir[store_path("store/#{id}--*")].first).sort

  def test_a_title_in_an_empty_store_opens_intent_1_with_its_rows_and_files
    assert_case line("intent new Build the thing"), code: 0, out: ["because: intent 1 has its rows and its files"]
    assert_equal [%w[1], FILES], [index_ids, files_of("1")]
  end

  def test_a_child_takes_the_next_letter_under_its_parent
    ran("intent new Parent")

    assert_case line("intent new Child --parent 1"), code: 0, out: ["because: intent 1a has its rows and its files"]
    assert_equal [%w[1 1a], FILES], [index_ids, files_of("1a")]
  end

  def test_a_ref_to_an_intent_of_this_installation_says_so
    ran("intent new Parent")

    assert_case line("intent new Second --ref 1-#{origin}"), code: 0, out: ["ref: intent 1 of this installation"]
    assert_equal [%w[1 2], FILES], [index_ids, files_of("2")]
  end

  def test_a_ref_to_a_ticket_is_kept_as_written
    assert_case line("intent new Ticketed --ref ENG-12"), code: 0, out: ["ref: ENG-12"]
    assert_equal [%w[1], FILES], [index_ids, files_of("1")]
  end

  def test_a_parent_that_does_not_exist_exits_1_and_writes_nothing
    assert_case line("intent new Orphan --parent 9"), code: 1, out: "", err: ["no intent 9 in this store to be the parent"]
    assert_empty index_ids
  end

  def test_a_ref_to_an_intent_that_does_not_exist_exits_1_and_writes_nothing_more
    ran("intent new Parent")

    assert_case line("intent new Second --ref 5-#{origin}"), code: 1, out: "", err: ["no intent 5 of this installation for the ref"]
    assert_equal %w[1], index_ids
  end

  def test_a_new_intent_with_the_status_done_exits_1_and_writes_nothing
    assert_case line("intent new Late --status done"), code: 1, out: "",
      err: ["a new intent takes the status open, parked or future, not done"]
    assert_empty index_ids
  end

  def test_a_store_that_still_has_index_md_exits_1_and_says_to_sync_up
    FileUtils.cp_r(File.join(File.expand_path("../../../fixtures/legacy_store", __dir__), "."), store_root)

    assert_case line("intent new Too soon"), code: 1, out: "",
      err: ["this store still has INDEX.md; run plastic sync up to import it first"]
  end

  def test_an_index_edited_by_hand_exits_1_and_says_to_sync_up_first
    ran("intent new First")
    write("store/index.json", "{}\n")

    assert_case line("intent new Second"), code: 1, out: ["next: plastic sync up"], err: ["store/index.json changed since its last print on this home, " \
      "by hand or in a copy from another home; run plastic sync up first to read it into rows"]
  end
end

class IntentNewTest < Plastic::TestCase
  IntentNew = Plastic::Commands::Intent::New

  def description = { name: IntentNew.tool_name, summary: Plastic::CLI::TABLE.dig(IntentNew.tool_name, 1), usage: IntentNew.usage_line, subject: IntentNew.subject,
                      arguments: IntentNew.arguments.map(&:to_h), options: IntentNew.options.map(&:to_h), writes: IntentNew.writes }

  def test_the_command_reads_its_title_and_names_its_switches
    assert_equal ["intent new", "Open an intent: write its rows and its folder",
      "plastic intent new TITLE... [--parent ID] [--ref REF] [--after ID] [--kind KIND] [--status STATUS] [--reason TEXT]", [:title]],
      description.values_at(:name, :summary, :usage, :subject)
    assert_equal({ name: :title, label: "TITLE", text: "what the intent is for, in words", rest: true, optional: false },
      description[:arguments].first)
  end

  def test_the_options_take_their_defaults
    assert_equal({ parent_id: nil, ref: nil, after: nil, kind: "work", status: "open", reason: nil },
      description[:options].to_h { |option| [option[:name], option[:default]] })
  end

  def test_the_command_writes_the_three_store_graphs_through_one_workflow
    assert_equal [%i[work knowledge references], true, [:code_write_intent]], [description[:writes], IntentNew.verify, IntentNew.chain.keys]
  end

  def test_the_intent_gets_a_document_row_and_a_file_named_intent_md
    result = plastic("intent", "new", "Alpha thing", table: Plastic::CLI::TABLE)
    row = store_graphs.databases.fetch(:knowledge).rows("SELECT path FROM documents WHERE intent_id = '1'").map { |doc| doc.fetch("path") }

    assert_equal 0, result.code
    assert_includes row, "intent.md"
    assert_path_exists store_path("store/1--alpha-thing/intent.md")
  end

  def test_the_intent_folder_holds_no_dated_file
    plastic("intent", "new", "Alpha thing", table: Plastic::CLI::TABLE)

    refute_path_exists store_path("store/1--alpha-thing/1--alpha-thing.md")
  end

  def test_the_slug_option_is_a_usage_error_and_writes_no_intent
    result = plastic("intent", "new", "Alpha", "--slug", "x", table: Plastic::CLI::TABLE)

    assert_equal 2, result.code
    assert_empty store_graphs.retrieval.intents
  end

  def test_after_writes_a_source_link_from_the_new_intent_to_id
    open_intent

    result = plastic("intent", "new", "Beta", "--after", "1", table: Plastic::CLI::TABLE)
    links = store_graphs.retrieval.links("1")

    assert_call result, code: 0, out: ["intent: 2\n"]
    assert_equal 1, links.size
  end

  def test_after_links_the_new_intent_to_id_as_a_source
    open_intent
    plastic("intent", "new", "Beta", "--after", "1", table: Plastic::CLI::TABLE)

    link = store_graphs.retrieval.links("1").first

    assert_equal ["2", "source"], [link.from_ref, link.kind]
  end

  def test_a_registered_project_with_no_store_folder_is_refused_and_gets_none
    home = Dir.mktmpdir
    File.write(File.join(home, "projects.yml"), "projects:\n  fresh:\n    path: #{Dir.mktmpdir}\n")
    result = plastic("intent", "new", "First", "--project", "fresh", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE)

    assert_equal [1, false], [result.code, Dir.exist?(File.join(home, "stores", "fresh"))]
    assert_includes result.out, "plastic project new fresh"
  end

  def test_after_naming_a_missing_intent_fails_with_no_intent_written
    result = plastic("intent", "new", "Beta", "--after", "9", table: Plastic::CLI::TABLE)

    assert_call result, code: 1, err: "plastic: no intent 9 in this store to link after\n"
    assert_empty store_graphs.retrieval.intents
  end

  def test_a_parked_intent_with_a_reason_keeps_both
    result = plastic("intent", "new", "Wait", "--status", "parked", "--reason", "waiting for the vendor", table: Plastic::CLI::TABLE)

    assert_equal [0, ["parked", "waiting for the vendor"]], [result.code, store_graphs.retrieval.intent("1").to_h.values_at(:status, :reason)]
  end

  def test_a_parked_intent_with_no_reason_is_refused_and_writes_nothing
    result = plastic("intent", "new", "Wait", "--status", "parked", table: Plastic::CLI::TABLE)

    assert_call result, code: 1, err: "plastic: a parked intent needs a reason: pass --reason TEXT\n"
    assert_empty store_graphs.retrieval.intents
  end

  def test_a_reason_on_an_open_intent_is_refused_and_writes_nothing
    result = plastic("intent", "new", "Wait", "--reason", "later", table: Plastic::CLI::TABLE)

    assert_call result, code: 1, err: "plastic: --reason belongs to a parked intent: pass --status parked\n"
    assert_empty store_graphs.retrieval.intents
  end

  def test_an_intent_does_not_start_in_progress
    result = plastic("intent", "new", "Go", "--status", "in_progress", table: Plastic::CLI::TABLE)

    assert_call result, code: 1, err: "plastic: a new intent takes the status open, parked or future, not in_progress\n"
    assert_empty store_graphs.retrieval.intents
  end
end
