# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceProseTest < Minitest::Test
  def test_a_code_block_is_fenced_and_a_paragraph_stays_plain
    lines = CommandReference::Markdown::Prose.lines(["Text one.", "", "  code line", "", "Text two."])

    assert_equal ["Text one.", "", "```ruby", "code line", "```", "", "Text two.", ""], lines
  end

  def test_a_comment_that_says_the_summary_again_repeats_it
    prose = CommandReference::Markdown::Prose

    assert prose.repeats?("List every store's open intents.", ["Every store under the home, its open intents."])
    refute prose.repeats?("Send the file.", ["Send the file to the person who asked for it, then wait a day for an answer and write down the reply."])
    refute prose.repeats?("Send the file.", [])
  end
end
