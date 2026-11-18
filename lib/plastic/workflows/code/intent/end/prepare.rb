# frozen_string_literal: true

require_relative "../end"
require_relative "../../../../code_workflow"
require_relative "../../../../graph/work/completion/check"
require_relative "../../../../graph/work/completion/review"
require_relative "../../../delivery_ownership"
require_relative "../../../pull_request_template"
require_relative "../../../review_round"

module Plastic
  module Workflows
    module Code
      module Intent
        class End
          # Reads what closing an intent needs: the rows, the judge's verdict, outcome.md and, by the review setting, the pull request.
          class Prepare < CodeWorkflow
            summary "Reads what closing the intent needs: the rows, the verdict, outcome.md and the review."
            sets :intent, :closed, :problem, :requirements, :judged, :used_up, :awaiting_approval, :intent_folder, :merge_recorded, :map_recorded, :merge_found, :approval_found, :template_found, :missing

            read "read the intent" do |context|
              context[:intent] = context.retrieval.intent(context.intent_id)
              context[:closed] = context.intent&.status == "done"
            end

            gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
            gate "intent %{intent_id} is not open or in progress", stops: :failure,
              pass: ->(context) { context.closed || Plastic::Graph::Knowledge::Intent::OPEN.include?(context.intent.status) }

            read "check delivery ownership" do |context|
              context[:problem] = DeliveryOwnership.problem(context)
            end

            gate "%{problem}", stops: :refusal,
              words: "another live session holds a node claim of the intent",
              pass: ->(context) { context.problem.nil? }

            read "check the completion records" do |context|
              context[:intent_folder] = context.intent.dir
              context[:requirements] = []
              context[:judged] = true
              context[:used_up] = false
              context[:awaiting_approval] = false
              context[:merge_recorded] = context[:map_recorded] = false
              context[:missing] = ""
              context[:merge_found] = context[:approval_found] = context[:template_found] = ""
              record_facts(context) unless context.closed
            end

            NOT_JUDGED = "No accepted review counts yet."

            def self.record_facts(context)
              check = Plastic::Graph::Work::Completion::Check.new(context.retrieval, context.intent_id)
              context[:requirements] = check.record_problems + (review_required?(context) ? pull_request_problems(check) : [])
              review_facts(context)
              verification_facts(context, check.verification)
            end

            def self.verification_facts(context, verification)
              context[:merge_recorded], context[:map_recorded] = [verification.merged?, verification.architecture_map?]
              found_facts(context, verification)
              context[:awaiting_approval] = review_required?(context) && ready_for_approval?(context) && !verification.approved?
            end

            def self.found_facts(context, verification)
              context[:merge_found] = merge_found(verification)
              context[:approval_found] = approval_found(verification)
              context[:template_found] = PullRequestTemplate.fact(context.scope, context.intent)
            end

            def self.merge_found(verification)
              found = verification.rejected("Merged")
              found ? "outcome.md says '#{found}', which is not a merge in the form 'Merged: <branch> into <base> at <commit or pull request>'. " : ""
            end

            def self.approval_found(verification)
              found = verification.rejected("Approved")
              found ? "outcome.md says '#{found}', which is not an approval in the form 'Approved: <person> on <YYYY-MM-DD>'; " : ""
            end

            def self.review_facts(context)
              review = Plastic::Graph::Work::Completion::Review.of(context)
              context[:judged] = review.counting?
              context[:missing] = (context.requirements + (context.judged ? [] : [NOT_JUDGED])).join(" ")
              context[:used_up] = review.used_up?
            end

            def self.review_required?(context)
              context.settings.config.choice(%w[review pull_request], default: "off", allowed: %w[required off]) == "required"
            end

            def self.pull_request_problems(check)
              check.verification.pull_request? ? [] : ["Add a line starting Pull request: to the Verification section of outcome.md and run plastic sync up."]
            end

            def self.ready_for_approval?(context) = context.requirements.empty? && context.judged

            gate ReviewRound::MESSAGE, stops: :refusal,
              pass: ->(context) { !context.used_up }
            gate "the pull request of intent %{intent_id} waits for the person's approval; %{approval_found}add the line 'Approved: <person> on <YYYY-MM-DD>' to the Verification section of outcome.md once they approve, then run plastic sync up",
              stops: :refusal, pass: ->(context) { !context.awaiting_approval }

            def self.verified?(context) = context.merge_recorded && context.map_recorded

            outcome :closed, if: ->(context) { context.closed }, found_by: "read the intent",
              offers: "plastic next", because: "intent %{intent_id} is already done"
            outcome :agent_needed, if: ->(context) { !context.requirements.empty? || !context.judged }, because: "the intent still needs records or a verdict before it can end"
            outcome :unverified, if: ->(context) { !verified?(context) }, because: "the merge of the work is not verified yet"
            outcome :ready, because: "the records, the verdict and the merge are in place"
          end
        end
      end
    end
  end
end
