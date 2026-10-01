# frozen_string_literal: true

require_relative "../support/kernel"
require_relative "../../../scripts/lib/plastic/commands/intent_new"

class IntentNewTest < Minitest::Test
  IntentNew = Plastic::Commands::IntentNew

  def description = IntentNew.describe.to_h

  def test_the_command_reads_its_title_and_names_its_switches
    assert_equal ["intent new", "Open an intent: write its rows and print its folder",
      "plastic intent new TITLE [--parent ID] [--ref REF] [--kind KIND] [--status STATUS] [--slug SLUG]", [:title]],
      description.values_at(:name, :summary, :usage, :subject)
    assert_equal({ name: :title, label: "TITLE", text: "what the intent is for, in words", rest: true, optional: false },
      description[:arguments].first)
  end

  def test_the_options_take_their_defaults
    assert_equal({ parent_id: nil, ref: nil, kind: "work", status: "open", slug: nil },
      description[:options].to_h { |option| [option[:name], option[:default]] })
  end

  def test_the_command_writes_the_three_store_graphs_through_one_workflow
    assert_equal [%i[work knowledge references], true, [:code_write_intent]], [description[:writes], IntentNew.verify, IntentNew.chain.keys]
  end
end
