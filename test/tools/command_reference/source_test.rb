# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceSourceTest < Minitest::Test
  include CommandReferenceHelper

  def source = CommandReference::Source.new(CommandReferenceHelper::ROOT)

  def test_the_comment_above_a_class_is_read_without_its_marker
    comment = source.class_comment(Plastic::Commands::IntentEnd)

    assert_equal ["Closes a delivered intent once the rows, the verdict and outcome.md allow it, and hands over what is missing."], comment
  end

  def test_a_lambda_body_is_read_on_one_line
    gate = Plastic::Workflows::PrepareEnding.steps.grep(Plastic::CodeWorkflow::Gate).first

    assert_equal "!context.intent.nil?", source.lambda_code(gate.pass)
  end

  def test_a_method_object_shows_its_method_body
    code = source.lambda_code(Plastic::Workflows::MoveNode.method(:moved?))

    assert_includes code, "context.moved == true"
  end

  def test_comment_lines_read_as_paragraphs_and_code_blocks
    blocks = source.blocks(["Text one", "more.", "", "  code line", "", "Text two."])

    assert_equal [[:text, "Text one more."], [:code, "code line"], [:text, "Text two."]], blocks
  end

  def test_a_path_is_relative_to_the_root
    assert_equal "scripts/lib/plastic/routine.rb", source.relative(File.join(CommandReferenceHelper::ROOT, "scripts/lib/plastic/routine.rb"))
  end
end
