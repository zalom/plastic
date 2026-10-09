# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_new"

class IntentNewTest < Plastic::TestCase
  IntentNew = Plastic::Commands::IntentNew

  def description = { name: IntentNew.tool_name, summary: Plastic::CLI::TABLE.dig(IntentNew.tool_name, 1), usage: IntentNew.usage_line, subject: IntentNew.subject,
                      arguments: IntentNew.arguments.map(&:to_h), options: IntentNew.options.map(&:to_h), writes: IntentNew.writes }

  def test_the_command_reads_its_title_and_names_its_switches
    assert_equal ["intent new", "Open an intent: write its rows and its folder",
      "plastic intent new TITLE... [--parent ID] [--ref REF] [--after ID] [--kind KIND] [--status STATUS]", [:title]],
      description.values_at(:name, :summary, :usage, :subject)
    assert_equal({ name: :title, label: "TITLE", text: "what the intent is for, in words", rest: true, optional: false },
      description[:arguments].first)
  end

  def test_the_options_take_their_defaults
    assert_equal({ parent_id: nil, ref: nil, after: nil, kind: "work", status: "open" },
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

    assert_call result, code: 1, out: RUN_ROW, err: "plastic: no intent 9 in this store to link after\n"
    assert_empty store_graphs.retrieval.intents
  end
end
