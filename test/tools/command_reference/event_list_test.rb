# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceEventListTest < Minitest::Test
  include CommandReferenceHelper

  WAYS = {
    records: /\AWhen the intent still needs records or a verdict/,
    merge: /\AWhen the merge of the work is not verified yet/,
    close: /\AWhen the records, the verdict and the merge are in place/
  }.freeze

  def listed(words) = CommandReference::EventList.new(page(words)).events

  def ways(words) = listed(words).filter_map(&:way)

  def test_each_way_after_a_branch_of_intent_end_starts_with_its_condition_in_the_order_of_the_delivery
    kinds = ways("intent end").map { |way| WAYS.find { |_name, pattern| way.match?(pattern) }&.first }

    assert_equal %i[records merge close], kinds
  end

  def test_no_way_of_intent_end_starts_joined_to_the_end_of_the_one_before
    starts = listed("intent end").select(&:way)

    assert_equal [false, false, false], starts.map(&:joined)
  end

  def test_every_event_of_intent_end_that_starts_no_way_is_joined
    assert(listed("intent end").drop(1).reject(&:way).all?(&:joined))
  end

  def test_the_ending_that_says_the_intent_is_done_hangs_on_the_read_that_finds_it
    holders = listed("intent end").select { |event| event.stops.any? { |stop| stop.text.include?("already done") } }

    assert_equal ["Read the intent."], holders.map(&:text)
  end

  def test_the_endings_that_no_call_can_reach_are_not_in_the_events_of_intent_end
    words = listed("intent end").flat_map { |event| event.stops.map(&:text) }
    unreachable = ["The completion records are ready.", "The merge and the architecture map are recorded.", "Nothing the intent started is left running."]

    assert_empty unreachable & words
  end

  Flow = Struct.new(:klass, :rows, :outcomes, :key) do
    def agent? = false
  end

  def flow_found_by(step_name)
    outcome = CommandReference::Outcome.new(name: :done, check: nil, fallback: true, offers: nil, because: "the thing is done", to: :noop, exit_code: 0, file: "thing.rb", line: 1, found_by: step_name)
    Flow.new(Struct.new(:steps).new([]), [], [outcome], "thing")
  end

  def test_an_ending_found_by_a_step_the_workflow_does_not_have_raises_with_both_names
    error = assert_raises(ArgumentError) { CommandReference::FlowStops.new(flow_found_by("read the moon")).events }

    assert_includes error.message, "read the moon"
    assert_includes error.message, "thing"
  end
end
