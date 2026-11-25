# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/hooks/guard"

# PreToolUse: the guard answers a refused write with the harness's deny decision and prints nothing for any other call.
class GuardHookTest < Plastic::TestCase
  def call(**event) = plastic("hook", "guard", input: JSON.generate(event), env: { "CLAUDE_CODE_SESSION_ID" => "s-1" }, table: Plastic::CLI::TABLE)

  def test_a_refused_write_prints_the_deny_decision_with_its_reason
    intent = open_intent
    result = call(tool_name: "Write", tool_input: { file_path: store_path("#{intent.dir}/spec.md") }, cwd: Dir.pwd)
    output = JSON.parse(result.out).fetch("hookSpecificOutput")

    assert_equal [0, "PreToolUse", "deny"], [result.code, output.fetch("hookEventName"), output.fetch("permissionDecision")]
    assert_includes output.fetch("permissionDecisionReason"), "plastic intent spec"
  end

  def test_an_allowed_write_prints_nothing
    intent = open_intent

    assert_call call(tool_name: "Write", tool_input: { file_path: store_path("#{intent.dir}/resources/tmp/a.md") }, cwd: Dir.pwd), code: 0, out: "", err: ""
  end

  def test_an_event_with_no_tool_prints_nothing
    assert_call call, code: 0, out: "", err: ""
  end
end
