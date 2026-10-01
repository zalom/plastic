# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_new"

class IntentNewTest < Plastic::TestCase
  IntentNew = Plastic::Commands::IntentNew

  def description = IntentNew.describe.to_h

  def test_the_command_reads_its_title_and_names_its_switches
    assert_equal ["intent new", "Open an intent: write its rows and print its folder",
      "plastic intent new TITLE [--parent ID] [--ref REF] [--after ID] [--kind KIND] [--status STATUS] [--slug SLUG]", [:title]],
      description.values_at(:name, :summary, :usage, :subject)
    assert_equal({ name: :title, label: "TITLE", text: "what the intent is for, in words", rest: true, optional: false },
      description[:arguments].first)
  end

  def test_the_options_take_their_defaults
    assert_equal({ parent_id: nil, ref: nil, after: nil, kind: "work", status: "open", slug: nil },
      description[:options].to_h { |option| [option[:name], option[:default]] })
  end

  def test_the_command_writes_the_three_store_graphs_through_one_workflow
    assert_equal [%i[work knowledge references], true, [:code_write_intent]], [description[:writes], IntentNew.verify, IntentNew.chain.keys]
  end

  def test_after_writes_a_source_link_from_the_new_intent_to_id
    open_intent

    result = plastic("intent", "new", "Beta", "--after", "1", table: Plastic::CLI::TABLE)
    links = store_graphs.retrieval.links("1")

    assert_equal 0, result.code
    assert_equal 1, links.size
  end

  def test_after_links_the_new_intent_to_id_as_a_source
    open_intent
    plastic("intent", "new", "Beta", "--after", "1", table: Plastic::CLI::TABLE)

    link = store_graphs.retrieval.links("1").first

    assert_equal ["2", "source"], [link.from_ref, link.kind]
  end

  def test_after_naming_a_missing_intent_fails_with_no_intent_written
    result = plastic("intent", "new", "Beta", "--after", "9", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    assert_empty store_graphs.retrieval.intents
  end
end
