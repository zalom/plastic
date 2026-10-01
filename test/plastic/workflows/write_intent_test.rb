# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/write_intent"

class WriteIntentTest < Plastic::TestCase
  WriteIntent = Plastic::Workflows::WriteIntent
  DECLARED = %i[title parent_id ref kind status slug problem intent_id printed_paths].freeze

  # The work graph as WriteIntent calls it, keeping each call.
  class Work
    Written = Data.define(:intent_id)

    attr_reader :calls

    def initialize(problem)
      @problem = problem
      @calls = []
    end

    def intent_problem(**call) = (@calls << [:problem, call]) && @problem

    def write_intent(**intent) = (@calls << [:write, intent]) && Written.new("1a")

    def print_intent(intent_id) = (@calls << [:print, intent_id]) && %w[store/index.json store/1a--build/1a--build.md]

    def ref_line(ref) = "ref: #{ref}, in words"
  end

  def run_flow(problem: nil, **facts)
    work = Work.new(problem)
    context = Plastic::Context.new(declared: DECLARED, facts: { title: "Build", status: "open", kind: "work" }.merge(facts),
      graphs: { work: })
    [WriteIntent.call(context), context.printed, work.calls]
  end

  def test_the_intent_is_written_then_printed_then_named
    outcome, printed, calls = run_flow(parent_id: "1", ref: "ENG-1", slug: "build")

    assert_equal :done, outcome
    assert_equal ["intent: 1a", "ref: ENG-1, in words", "printed store/index.json", "printed store/1a--build/1a--build.md"], printed
    assert_equal [[:problem, { parent_id: "1", ref: "ENG-1", status: "open" }],
      [:write, { title: "Build", parent_id: "1", ref: "ENG-1", kind: "work", status: "open", slug: "build" }], [:print, "1a"]], calls
  end

  def test_no_ref_prints_no_ref_line
    assert_equal ["intent: 1a", "printed store/index.json", "printed store/1a--build/1a--build.md"], run_flow[1]
  end

  def test_a_problem_fails_the_call_before_any_write
    outcome, printed, calls = run_flow(problem: "no intent 9 in this store to be the parent")

    assert_equal [Plastic::Failed, "code_write_intent, gate: no intent 9 in this store to be the parent"], [outcome.class, outcome.message]
    assert_equal [[], [:problem]], [printed, calls.map(&:first)]
  end

  def test_the_outcome_offers_the_next_command_and_names_the_intent
    outcome = WriteIntent.outcomes.first

    assert_equal [:done, "plastic continue", "intent %{intent_id} has its rows and its printed files"],
      [outcome.name, outcome.offers, outcome.because]
  end

  def test_a_second_load_keeps_one_chain
    before = [run_flow(ref: "ENG-1")[1], run_flow[1]]
    load File.expand_path("../../../scripts/lib/plastic/workflows/write_intent.rb", __dir__)

    assert_equal [before, [:done]], [[run_flow(ref: "ENG-1")[1], run_flow[1]], WriteIntent.outcome_names]
  end
end
