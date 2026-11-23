# frozen_string_literal: true

require_relative "../workflow"
require_relative "../graph/knowledge/spec"
require_relative "../graph/work/completion/work_check"

module Plastic
  class CodeWorkflow < Workflow
    # The gate that refuses a call while a done criterion of the spec has no done node serving it. It reads the same
    # WorkCheck method that `plastic intent end` reads, so an accept never leaves an intent that cannot end.
    module CriteriaCoverageGate
      UNCOVERED = lambda do |context|
        keys = Plastic::Graph::Knowledge::Spec.new(context.retrieval, context.intent_id).criteria_by_key.keys
        Plastic::Graph::Work::Completion::WorkCheck.new(context.retrieval, context.intent_id, keys).uncovered_keys.join(", ")
      end

      # `applies` says when the rule holds for the call; a call it does not cover passes.
      def criteria_coverage_gate(applies: ->(_context) { true })
        sets :uncovered
        read("find the done criteria no done node serves") { |context| context[:uncovered] = applies.call(context) ? UNCOVERED.call(context) : "" }
        gate "no done node serves the done criteria of intent %{intent_id}: %{uncovered}; add a node for each with plastic node add %{intent_id} TITLE --criterion KEY, then claim it and finish it",
          stops: :refusal, offers: "plastic node add %{intent_id} TITLE --criterion KEY",
          because: "an accept needs every done criterion served by a done node, or the intent cannot end",
          pass: ->(context) { context.uncovered.to_s.empty? }
      end
    end
  end
end
