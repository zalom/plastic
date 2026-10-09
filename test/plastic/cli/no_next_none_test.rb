# frozen_string_literal: true

require_relative "../../test_helper"

class NoNextNoneTest < Plastic::TestCase
  def next_lines(result) = result.out.lines(chomp: true).grep(/\Anext: /)

  def test_nothing_open_prints_no_next_line_and_says_why
    result = plastic("next", table: Plastic::CLI::TABLE)

    assert_equal [0, [], ""], [result.code, next_lines(result), result.err]
    assert_includes result.out, "because: nothing is open"
  end

  def test_a_hand_off_with_no_command_prints_no_next_line_and_says_why
    intent = open_intent
    write("#{intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- [done] ships\n")
    plastic("sync", "up", table: Plastic::CLI::TABLE)
    result = plastic("next", table: Plastic::CLI::TABLE)

    assert_equal [0, []], [result.code, next_lines(result)]
    assert_includes result.out, "because: the owner must give the go-ahead for intent 1"
  end

  def test_json_names_a_null_next_when_nothing_is_open
    result = plastic("next", "--json", table: Plastic::CLI::TABLE)
    answer = JSON.parse(result.out)

    assert_nil answer.fetch("next")
    assert_equal "nothing is open", answer.fetch("because")
  end

  def test_json_error_with_no_offer_names_a_null_next
    result = plastic("intent", "show", "99", "--json", table: Plastic::CLI::TABLE)
    answer = JSON.parse(result.out)

    assert_nil answer.fetch("next")
    refute_equal "none", answer.fetch("next")
  end

  def test_a_search_with_no_hit_on_a_fresh_home_prints_no_next_line_and_exits_0
    result = plastic("search", "nothing-matches-this", table: Plastic::CLI::TABLE)

    assert_equal [0, [], ""], [result.code, next_lines(result), result.err]
  end

  def test_a_document_lookup_that_finds_nothing_prints_no_next_line
    result = plastic("document", "get", "plastic://global/1/spec.md", table: Plastic::CLI::TABLE)

    assert_equal [1, []], [result.code, next_lines(result)]
    refute_includes result.out, "retrieval migration"
  end

  def test_no_command_text_output_has_no_closing_next_line
    output = Plastic::CLI::Result.new.tap { |answer| answer.offer(nil, "a reason") }

    assert_equal ["because: a reason"], output.closing_lines(nil)
  end
end
