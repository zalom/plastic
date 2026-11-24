# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncClosedEditsTest < Plastic::TestCase
  include LifecycleHelper

  ClosedEdits = Plastic::Graph::Knowledge::Sync::ClosedEdits
  OUTCOME = "# Outcome\n\nDropped: the need went away.\n\n## Verification\n- Abandoned: dropped because the need went away\n"

  def setup
    super
    @intent = open_intent
    write("#{@intent.dir}/outcome.md", OUTCOME)
    sync_up
  end

  def abandoned
    cli("intent", "abandon", "1")
    @intent
  end

  def edits(*names) = ClosedEdits.new(retrieval).call(names.map { |name| "#{@intent.dir}/#{name}" })

  def test_the_spec_and_the_outcome_of_a_closed_intent_are_each_named_with_the_reason
    abandoned
    reason = "intent 1 is abandoned, and a closed intent keeps its %s as it closed"

    assert_equal({ "#{@intent.dir}/spec.md" => format(reason, "spec.md"), "#{@intent.dir}/outcome.md" => format(reason, "outcome.md") },
      edits("spec.md", "outcome.md"))
  end

  def test_the_spec_of_an_open_intent_is_not_named
    assert_empty edits("spec.md", "outcome.md")
  end

  def test_other_files_of_a_closed_intent_are_not_named
    abandoned

    assert_empty edits("graph.json", "resources/tmp/notes.md")
  end
end
