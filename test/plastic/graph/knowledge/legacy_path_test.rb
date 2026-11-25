# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeLegacyPathTest < Plastic::TestCase
  LegacyPath = Plastic::Graph::Knowledge::LegacyPath

  def test_plan_checklist_and_actions_are_legacy_and_spec_is_not
    legacy = ["plan.md", "checklist.md", "actions/ACTION_1.md", "actions/.gitkeep", "actions/deep/note.md"]
    other = ["spec.md", "outcome.md", "resources/plan.md", "notes/checklist.md", "my_actions/a.md", "actions.md", "1--alpha.md"]

    assert_equal [legacy.map { true }, other.map { false }], [legacy.map { |rel| LegacyPath.legacy?(rel) }, other.map { |rel| LegacyPath.legacy?(rel) }]
  end
end
