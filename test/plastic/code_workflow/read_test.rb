# frozen_string_literal: true

require_relative "../../test_helper"

class CodeWorkflowReadTest < Plastic::TestCase
  def test_a_read_runs_its_body_and_never_ends_the_call
    ctx = context
    read = Plastic::CodeWorkflow::Read.new(name: "say", body: ->(c) { c.print("hello #{c.name}") })

    assert_nil read.run(ctx, Flows::Greet)
    assert_equal ["hello ada"], ctx.printed
  end
end
