# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/status"

class StatusTest < Plastic::TestCase
  def call(*args) = plastic("status", *args, table: Plastic::CLI::TABLE)

  def test_a_second_store_is_not_missed
    open_intent
    Plastic::Graph.open(home: @plastic_home, store: "other").work.write_intent(title: "Beta")

    result = call

    assert_equal 0, result.code
    assert_includes result.out, "other"
    assert_includes result.out, "Beta"
  end

  def test_offers_next
    open_intent

    result = call

    assert_includes result.out, "next: plastic next"
  end
end
