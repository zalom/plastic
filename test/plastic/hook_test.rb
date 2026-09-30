# frozen_string_literal: true

require "json"
require_relative "support/kernel"

class HookTest < Minitest::Test
  include KernelFixtures::Calls

  def setup = make_home

  def teardown = remove_home

  def test_a_hook_prints_its_reply_as_one_json_object
    call = plastic("hook", "echo", input: %({"session_id": "s-1"}))

    assert_equal 0, call.code
    assert_equal({"hookSpecificOutput" => {"hookEventName" => "SessionStart", "additionalContext" => "session s-1"}},
      JSON.parse(call.out))
  end

  def test_a_hook_with_no_input_reads_an_empty_event
    assert_equal "session ", JSON.parse(plastic("hook", "echo", input: "  ").out).dig("hookSpecificOutput", "additionalContext")
  end

  def test_a_hook_with_no_reply_prints_nothing
    call = plastic("hook", "quiet")

    assert_equal [0, "", ""], [call.code, call.out, call.err]
  end

  def test_a_broken_event_still_exits_0
    call = plastic("hook", "echo", input: "{not json")

    assert_equal [0, ""], [call.code, call.out]
    assert_match(/\Aplastic hook: JSON::ParserError: /, call.err)
  end

  def test_a_hook_must_define_respond
    err = StringIO.new
    code = Plastic::Hook.call([], out: StringIO.new, err:, words: "hook", environment: environment)

    assert_equal 0, code
    assert_equal "plastic hook: NoMethodError: Plastic::Hook must define respond\n", err.string
  end
end
