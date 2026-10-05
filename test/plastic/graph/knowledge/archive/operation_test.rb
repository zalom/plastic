# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveOperationTest < Plastic::TestCase
  Steps = Struct.new(:answer, :taken) do
    def problem(_intent) = answer

    def capture(intent) = taken << [:capture, intent.intent_id]

    def call(intent) = taken << [:complete, intent.intent_id]
  end

  def setup
    super
    store_graphs.work.write_intent(title: "Target", status: "done")
  end

  def run_with(answer)
    steps = Steps.new(answer, [])
    [Plastic::Graph::Knowledge::Archive::Operation.new(retrieval, steps, steps, steps).call(@intent_id || "1"), steps.taken]
  end

  def test_an_allowed_intent_is_captured_then_completed
    assert_equal [[true, nil, nil], [[:capture, "1"], [:complete, "1"]]], run_with(nil)
  end

  def test_a_refused_intent_is_neither_captured_nor_completed
    assert_equal [[false, "no", :refusal], []], run_with("no")
  end

  def test_a_missing_intent_fails
    @intent_id = "9"

    assert_equal [[false, "no intent 9", :failure], []], run_with(nil)
  end

  def test_an_archived_intent_only_finishes_its_completion
    store_graphs.databases[:work].transaction do |batch|
      batch.put(:archives, { intent_id: "1", at: STAMP, restored_at: nil, session_id: nil })
    end

    assert_equal [[true, nil, nil], [[:complete, "1"]]], run_with("ignored")
  end
end
