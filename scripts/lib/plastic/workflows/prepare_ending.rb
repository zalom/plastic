# frozen_string_literal: true

require "json"
require_relative "../code_workflow"
require_relative "../graph/work/completion/check"

module Plastic
  module Workflows
    # Reads closure prerequisites and the explicit criterion attestation.
    class PrepareEnding < CodeWorkflow
      sets :intent, :closed, :problem, :requirements, :attestation, :evidence_example, :intent_folder

      read "read the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
        context[:closed] = context.intent&.status == "done"
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
      gate "intent %{intent_id} is not open or active", stops: :failure,
        pass: ->(context) { context.closed || context.intent.open? }

      read "check delivery ownership" do |context|
        lock = context.retrieval.lock(context.intent_id)
        context[:problem] = (lock && lock.session_id != context.session && lock.live?) ? "intent #{context.intent_id} is locked by session #{lock.session_id}" : nil
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      read "check the completion records" do |context|
        check = Graph::Work::Completion::Check.new(context.retrieval, context.intent_id)
        context[:requirements] = context.closed ? [] : check.problems
        context[:evidence_example] = JSON.pretty_generate(check.criteria.to_h { |criterion| [criterion, "Describe the evidence for this criterion"] })
        context[:intent_folder] = context.intent.dir
        context[:attestation] = nil
        context[:problem] = evidence_problem(context, check)
      end

      def self.evidence_problem(context, check)
        return nil if context.closed || (context.judge.nil? && context.evidence.nil?)
        problem = submission_problem(context)
        return problem if problem

        context[:attestation] = context.work.completion_evidence(context.intent_id, context.evidence, check.criteria)
        nil
      rescue Invalid => error
        error.message
      end

      def self.submission_problem(context)
        return "--judge takes tests, tool, agent or owner" unless Graph::Work::Node::JUDGES.include?(context.judge)
        return "--evidence names a JSON file inside the intent folder" if context.evidence.to_s.empty?
        return "intent end names no session" if context.session.to_s.empty?

        nil
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      outcome :closed, if: ->(context) { context.closed }
      outcome :ready, if: ->(context) { context.requirements.empty? && !context.attestation.nil? }
      outcome :agent_needed
    end
  end
end
