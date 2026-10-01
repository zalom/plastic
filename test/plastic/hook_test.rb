# frozen_string_literal: true

require_relative "../test_helper"

class HookTest < Plastic::TestCase
  def test_a_hook_prints_its_reply_as_plain_text
    call = plastic("hook", "echo", input: %({"session_id": "s-1"}))

    assert_equal [0, "session s-1\n"], [call.code, call.out]
  end

  def test_a_hook_with_no_input_reads_an_empty_event
    assert_equal "session \n", plastic("hook", "echo", input: "  ").out
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
    code = Plastic::Hook.call([], words: "hook", environment: environment(err:))

    assert_equal 0, code
    assert_equal "plastic hook: NoMethodError: Plastic::Hook must define respond\n", err.string
  end
end
