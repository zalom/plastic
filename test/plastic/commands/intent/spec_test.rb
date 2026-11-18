# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/spec"

class IntentSpecCaseTest < Plastic::TestCase
  def test_the_spec_of_a_missing_intent_exits_1_and_names_it
    assert_case line("intent spec 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class IntentSpecTest < Plastic::TestCase
  def call(*args) = plastic("intent", "spec", *args, table: Plastic::CLI::TABLE)

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end

  def test_the_grilling_method_always_prints
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")

    result = call(intent.intent_id)

    assert_includes result.out, "# The grilling"
  end

  def test_the_spec_line_shows_one_example_criterion
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")

    assert_includes call(intent.intent_id).out, "spec: the done criteria are the bullets under its \"## Done criteria\" heading, each written - [c1] text"
  end

  def test_an_open_decision_is_printed
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Open Questions\n- which store wins\n")

    result = call(intent.intent_id)

    assert_equal [0, "# The grilling", ""], [result.code, result.out.lines.first.chomp, result.err]
    assert_includes result.out, "open: which store wins"
    assert_includes result.out, "next: plastic intent rule #{intent.intent_id} TEXT"
  end

  def test_a_clear_spec_without_a_go_ahead_offers_the_approve_command
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")

    result = call(intent.intent_id)

    refute_includes result.out, "open:"
    assert_call result, code: 0, err: "", out: ["next: plastic intent approve #{intent.intent_id}"]
  end

  def test_a_clear_spec_with_a_go_ahead_offers_the_approve_command
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")
    plastic("intent", "approve", intent.intent_id, table: Plastic::CLI::TABLE)

    result = call(intent.intent_id)

    assert_equal "# The grilling", result.out.lines.first.chomp
    refute_includes result.out, "open:"
    assert_call result, code: 0, err: "", out: ["next: plastic intent approve #{intent.intent_id}"]
  end

  def test_no_spec_misses_no_open_decision
    intent = open_intent

    result = call(intent.intent_id)

    assert_equal [0, "# The grilling", ""], [result.code, result.out.lines.first.chomp, result.err]
    refute_includes result.out, "open:"
    assert_includes result.out, "next: plastic sync up"
  end
end
