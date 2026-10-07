# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../varar/support/kernel_command"

class IntentReviseCommandTest < Minitest::Test
  def test_the_command_revises_an_intent_in_a_child_process
    Dir.mktmpdir do |home|
      kernel = KernelCommand.new(home)
      kernel.run!("intent", "new", "Alpha")

      call = kernel.run("intent", "revise", "1", "Beta, after grilling", "--why", "The owner moved the goal")

      assert_equal [0, ""], [call.code, call.err]
      assert_includes call.out, "what: Beta, after grilling"
      assert_equal [["Beta, after grilling"]], kernel.rows("work_graph.db", "SELECT title FROM intents")
    end
  end
end
