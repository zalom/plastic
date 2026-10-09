# frozen_string_literal: true

require "json"
require_relative "../code_workflow"
require_relative "../graph/work/completion/check"

module Plastic
  module Workflows
    # Reads closure prerequisites and the explicit criterion attestation. An abandoned close reads only the outcome.
    class PrepareEnding < CodeWorkflow
      ENDINGS = {
        false => { reached: "done", statuses: %w[open active], text: "open or active" },
        true => { reached: "abandoned", statuses: %w[open active parked future], text: "open, active, parked or future" }
      }.freeze

      sets :intent, :closed, :closable, :ending, :problem, :requirements, :attestation, :evidence_example, :intent_folder,
        :merge_recorded, :map_recorded

      read "read the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
        context[:ending] = ENDINGS.fetch(context.abandoned == true)
        context[:closable] = context.ending.fetch(:text)
        context[:closed] = context.intent&.status == context.ending.fetch(:reached)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
      gate "intent %{intent_id} is not %{closable}", stops: :failure,
        pass: ->(context) { context.closed || context.ending.fetch(:statuses).include?(context.intent.status) }

      read "check delivery ownership" do |context|
        lock = context.retrieval.lock(context.intent_id)
        context[:problem] = (lock && lock.session_id != context.session && lock.live?) ? "intent #{context.intent_id} is locked by session #{lock.session_id}" : nil
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      read "check the completion records" do |context|
        check = Graph::Work::Completion::Check.new(context.retrieval, context.intent_id)
        context[:intent_folder] = context.intent.dir
        context[:attestation] = nil
        context[:requirements] = []
        context[:problem] = context.abandoned ? abandon_problem(context, check) : delivery_problem(context, check)
      end

      def self.abandon_problem(context, check) = (check.abandon_problems.first unless context.closed)

      def self.delivery_problem(context, check)
        record_facts(context, check)
        context[:evidence_example] = JSON.pretty_generate(check.criteria.transform_values { "Describe the evidence for this criterion" })
        evidence_problem(context, check)
      end

      def self.record_facts(context, check)
        context[:requirements] = check.record_problems unless context.closed
        context[:merge_recorded], context[:map_recorded] = check.verification.then { |found| [found.merged?, found.architecture_map?] }
      end

      def self.evidence_problem(context, check)
        return unless submitted?(context)

        submission_problem(context) || attest(context, check)
      rescue Invalid => error
        error.message
      end

      def self.attest(context, check)
        context[:attestation] = context.work.completion_evidence(context.intent_id, context.evidence, check.criteria.keys)
        nil
      end

      def self.submitted?(context) = !context.closed && [context.judge, context.evidence].any?

      def self.submission_problem(context)
        return "--judge takes tests, tool, agent or owner" unless %w[tests tool agent owner].include?(context.judge)
        return "--evidence names a JSON file inside the intent folder" if context.evidence.to_s.empty?
        return "intent end names no session" if context.session.to_s.empty?

        nil
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      def self.verified?(context) = context.merge_recorded && context.map_recorded

      outcome :abandoning, if: ->(context) { context.abandoned }
      outcome :closed, if: ->(context) { context.closed }
      outcome :ready, if: ->(context) { context.requirements.empty? && verified?(context) && !context.attestation.nil? }
      outcome :unverified, if: ->(context) { context.requirements.empty? && !verified?(context) }
      outcome :agent_needed
    end
  end
end
