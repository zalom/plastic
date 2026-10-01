# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_spec"

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

  def test_an_open_decision_is_printed
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Open Questions\n- which store wins\n")

    result = call(intent.intent_id)

    assert_includes result.out, "open: which store wins"
  end

  def test_no_spec_misses_no_open_decision
    intent = open_intent

    result = call(intent.intent_id)

    refute_includes result.out, "open:"
  end
end
