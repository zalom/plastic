require "minitest/autorun"
require_relative "../scripts/lib/bridge"

# Intent 84, Lever 1: the gate-hook narration is ONE concise sentence that states
# what happened and preserves the `Next: ...` hint. No "Stage transition" prose,
# no arrow. Tested against the pure formatter Bridge.gate_narration so no hook or
# bridge resolution is needed.
class GateCheckOutputTest < Minitest::Test
  def test_transition_is_one_sentence_with_next_hint
    out = Bridge.gate_narration(
      old_stage: "why", new_stage: "how",
      basename: "plan.md", new_missing: []
    )

    refute_includes out, "\n", "must be a single line"
    refute_includes out, "Stage transition", "no transition prose"
    refute_includes out, "→", "no arrow"
    assert_includes out, "How"
    assert_includes out, "plan.md"
    assert_includes out, "Next:"
    # The stage hint for `how` is preserved verbatim.
    assert_includes out, Bridge::NEXT_HINTS["how"]
  end

  def test_missing_files_take_precedence_over_stage_hint
    out = Bridge.gate_narration(
      old_stage: "why", new_stage: "how",
      basename: "plan.md", new_missing: ["actions/", "checklist.md"]
    )

    assert_includes out, "Next: actions/, checklist.md"
    refute_includes out, Bridge::NEXT_HINTS["how"],
      "missing-files hint must override the stage hint"
  end

  def test_same_stage_write_form
    out = Bridge.gate_narration(
      old_stage: "how", new_stage: "how",
      basename: "checklist.md", new_missing: []
    )

    refute_includes out, "reached", "same-stage write uses the written form"
    assert_includes out, "checklist.md written (How)"
    refute_includes out, "→"
  end

  def test_no_next_when_no_missing_and_no_hint
    # `what` has no NEXT_HINTS entry; with nothing missing there is no Next clause.
    out = Bridge.gate_narration(
      old_stage: "what", new_stage: "what",
      basename: "5--x.md", new_missing: []
    )

    refute_includes out, "Next:"
    refute_includes out, "\n"
  end
end
