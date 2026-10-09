# frozen_string_literal: true

require_relative "../test_helper"

class CodeWorkflowTest < Plastic::TestCase
  def test_a_code_outcome_takes_no_stops
    error = assert_raises(Plastic::Invalid) { code { outcome :done, because: "x", stops: :failure } }

    assert_includes error.message, "outcome done takes no stops:"
  end

  def test_a_code_workflow_with_no_outcome_line_ends_on_done
    assert_equal [:done], Flows::Stamp.outcome_names
    assert_equal :done, Flows::Stamp.call(context(declared: %i[stamp], facts: {}))
  end

  def test_the_first_outcome_whose_check_holds_is_picked
    flow = code do
      outcome :first, if: ->(_c) { false }, because: "first"
      outcome :second, if: ->(_c) { true }, because: "second"
      outcome :rest, because: "rest"
    end

    assert_equal %i[first second rest], flow.outcome_names
    assert_equal :second, flow.call(context)
  end

  def test_the_fallback_is_picked_when_no_check_holds
    flow = code do
      outcome :first, if: ->(_c) { false }, because: "first"
      outcome :rest, because: "rest"
    end

    assert_equal :rest, flow.call(context)
    assert_empty flow.problems
  end

  def test_a_workflow_with_no_outcome_line_has_no_problem
    assert_empty Flows::Stamp.problems
  end

  def test_code_templates_include_the_gate_reasons
    assert_equal ["passed %{mode}", "the owner holds %{mode}", "the check broke on %{mode}"], Flows::Hold.templates
  end

  def test_a_done_step_is_skipped
    ran = []
    flow = code do
      step("once", done: ->(_c) { true }) { |_c| ran << :body }
    end

    assert_equal :done, flow.call(context)
    assert_empty ran
  end

  def test_a_read_runs_on_every_call
    ctx = context(declared: %i[name dir draft_path], facts: { name: "ada", dir: "/d" })
    Flows::FindDraft.call(ctx)

    assert_equal "/d/ada.md", ctx.draft_path
  end

  def test_a_refusal_gate_returns_a_refused_value
    assert_equal Plastic::Refused.new(:code_hold, "the owner holds hold"), Flows::Hold.call(context(facts: { mode: "hold" }))
  end

  def test_a_usage_error_raised_in_a_step_is_not_wrapped
    flow = code do
      read("misuse") { |_c| raise Plastic::CLI::Command::Usage, "bad input" }
    end

    assert_raises(Plastic::CLI::Command::Usage) { flow.call(context) }
  end

  def test_a_failure_gate_returns_a_failed_value
    assert_equal Plastic::Failed.new(:code_hold, "gate", "the check broke on break"),
      Flows::Hold.call(context(facts: { mode: "break" }))
  end
end

class CodeWorkflowGateOffersTest < Plastic::TestCase
  def test_a_failing_gate_with_offers_exits_1_and_prints_its_next_line
    call = plastic("kernel", "offer", "break")

    assert_equal 1, call.code
    assert_equal "next: plastic kernel two break\nbecause: the check broke on break\n", call.out
    assert_equal "plastic: the check broke on break\n", call.err
  end

  def test_a_failing_gate_with_offers_carries_the_command_in_json
    call = plastic("kernel", "offer", "break", "--json")
    document = JSON.parse(call.out)

    assert_equal 1, call.code
    assert_equal "plastic kernel two break", document.fetch("next")
    assert_equal "the check broke on break", document.fetch("because")
    assert_equal "", call.err
  end

  def test_a_failing_gate_without_offers_prints_no_next_line
    call = plastic("kernel", "offer", "plain")

    assert_equal 1, call.code
    refute_includes call.out, "next:"
    assert_equal "plastic: nothing follows plain\n", call.err
  end

  def test_a_refusal_gate_may_offer_a_command_too
    call = plastic("kernel", "offer", "hold")

    assert_equal 3, call.code
    assert_equal "next: plastic kernel two hold\nbecause: the owner holds hold\n", call.out
    assert_includes call.err, "plastic: refused, the owner holds hold"
  end

  def test_a_gate_that_passes_still_ends_the_chain_normally
    call = plastic("kernel", "offer", "fine")

    assert_equal 0, call.code
    assert_includes call.out, "because: passed fine"
  end
end
