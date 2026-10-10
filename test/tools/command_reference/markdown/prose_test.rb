# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceProseTest < Minitest::Test
  def test_a_code_block_is_fenced_and_a_paragraph_stays_plain
    lines = CommandReference::Markdown::Prose.lines(["Text one.", "", "  code line", "", "Text two."])

    assert_equal ["Text one.", "", "```ruby", "code line", "```", "", "Text two.", ""], lines
  end
end
