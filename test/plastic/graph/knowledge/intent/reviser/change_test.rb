# frozen_string_literal: true

require_relative "../../../../../test_helper"

class IntentReviserChangeTest < Plastic::TestCase
  Change = Plastic::Graph::Knowledge::Intent::Reviser::Change
  Intent = Struct.new(:intent_id, :title)
  Document = Struct.new(:path, :body)

  def change = Change.new(intent: Intent.new("7", "Old"), document: Document.new("7--x/intent.md", "# Old\n\n## Why\n\nBecause.\n"), history: nil, line: "New", why: "Because.")

  def test_the_change_names_its_intent
    assert_equal "7", change.intent_id
  end

  def test_the_log_text_is_the_new_title
    assert_equal "title: New", change.title_text
  end

  def test_the_log_fields_are_the_path_and_the_new_body
    assert_equal ["7--x/intent.md", change.body], change.log_fields.values_at(:path, :body)
  end
end
