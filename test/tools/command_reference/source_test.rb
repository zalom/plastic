# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceSourceTest < Minitest::Test
  module Sample
    def self.checked?(context)
      context.ready == true
    end
  end

  include CommandReferenceHelper

  def setup = CommandReferenceHelper.pages

  def source = CommandReference::Source.new(CommandReferenceHelper::ROOT)

  def test_a_lambda_body_is_read_on_one_line
    gate = Plastic::Workflows::Code::Intent::End::Prepare.steps.grep(Plastic::CodeWorkflow::Gate).first

    assert_equal "!context.intent.nil?", source.lambda_code(gate.pass)
  end

  def test_a_method_object_shows_its_method_body
    code = source.lambda_code(Plastic::Workflows::MoveNode.method(:moved?))

    assert_includes code, "context.moved == true"
  end

  def test_a_method_object_of_several_lines_shows_its_lines_up_to_the_closing_end
    assert_equal "def self.checked?(context) context.ready == true end", source.lambda_code(Sample.method(:checked?))
  end

  def test_a_path_is_relative_to_the_root
    assert_equal "lib/plastic/routine.rb", source.relative(File.join(CommandReferenceHelper::ROOT, "lib/plastic/routine.rb"))
  end
end
