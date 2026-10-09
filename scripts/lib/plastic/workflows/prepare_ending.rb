# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../config"
require_relative "../graph/work/completion/check"
require_relative "../graph/work/completion/review"
require_relative "delivery_ownership"
require_relative "review_round"

module Plastic
  module Workflows
    # Reads what closing an intent needs: the rows, the judge's verdict, outcome.md and, by the review setting, the pull request.
    class PrepareEnding < CodeWorkflow
      sets :intent, :closed, :problem, :requirements, :judged, :used_up, :awaiting_approval, :intent_folder, :merge_recorded, :map_recorded, :missing

      read "read the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
        context[:closed] = context.intent&.status == "done"
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
      gate "intent %{intent_id} is not open or active", stops: :failure,
        pass: ->(context) { context.closed || %w[open active].include?(context.intent.status) }

      read "check delivery ownership" do |context|
        context[:problem] = DeliveryOwnership.problem(context)
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      read "check the completion records" do |context|
        context[:intent_folder] = context.intent.dir
        context[:requirements] = []
        context[:judged] = true
        context[:used_up] = false
        context[:awaiting_approval] = false
        context[:merge_recorded] = context[:map_recorded] = false
        context[:missing] = ""
        record_facts(context) unless context.closed
      end

      NOT_JUDGED = "No accepted review counts yet."

      def self.record_facts(context)
        check = Graph::Work::Completion::Check.new(context.retrieval, context.intent_id)
        context[:requirements] = check.record_problems + (review_required?(context) ? pull_request_problems(check) : [])
        review_facts(context)
        verification_facts(context, check.verification)
      end

      def self.verification_facts(context, verification)
        context[:merge_recorded], context[:map_recorded] = [verification.merged?, verification.architecture_map?]
        context[:awaiting_approval] = review_required?(context) && ready_for_approval?(context) && !verification.approved?
      end

      def self.review_facts(context)
        review = Graph::Work::Completion::Review.of(context)
        context[:judged] = review.counting?
        context[:missing] = (context.requirements + (review.counting? ? [] : [NOT_JUDGED])).join(" ")
        context[:used_up] = review.used_up?
      end

      def self.review_required?(context)
        Config.new(context.scope.plastic_home).choice(%w[review pull_request], default: "required", allowed: %w[required off]) == "required"
      end

      def self.pull_request_problems(check)
        check.verification.pull_request? ? [] : ["Add a line starting Pull request: to the Verification section of outcome.md and run plastic sync up."]
      end

      def self.ready_for_approval?(context) = context.requirements.empty? && context.judged

      gate ReviewRound::MESSAGE, stops: :refusal,
        pass: ->(context) { !context.used_up }
      gate "the pull request of intent %{intent_id} waits for the person's approval; add the line Approved: to the Verification section of outcome.md once they approve, then run plastic sync up",
        stops: :refusal, pass: ->(context) { !context.awaiting_approval }

      def self.verified?(context) = context.merge_recorded && context.map_recorded

      outcome :closed, if: ->(context) { context.closed },
        offers: "plastic next", because: "intent %{intent_id} is already done"
      outcome :agent_needed, if: ->(context) { !context.requirements.empty? || !context.judged }
      outcome :unverified, if: ->(context) { !verified?(context) }
      outcome :ready
    end
  end
end
