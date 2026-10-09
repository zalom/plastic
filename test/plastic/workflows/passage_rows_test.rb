# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/passage_rows"

class PassageRowsTest < Minitest::Test
  ROW = { "body" => "text", "score" => -1.5, "uri" => "plastic://a/1/b.md", "store" => "a", "intent_id" => "1", "path" => "b.md" }.freeze

  def test_rows_are_ranked_from_one_in_the_order_given
    rows = Plastic::Workflows::PassageRows.new.call([ROW, ROW])

    assert_equal [1, 2], rows.map { |row| row.fetch("rank") }
  end

  def test_a_row_keeps_the_passage_and_uri_and_drops_the_body_and_score
    row = Plastic::Workflows::PassageRows.new(passage_of: ->(hit) { hit.fetch("body").upcase }).call([ROW]).first

    assert_equal({ "rank" => 1, "passage" => "TEXT", "uri" => "plastic://a/1/b.md", "store" => "a", "intent_id" => "1", "path" => "b.md" }, row)
  end
end
