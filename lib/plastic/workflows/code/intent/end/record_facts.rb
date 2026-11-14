# frozen_string_literal: true

require_relative "../../../../config"

module Plastic
  module Workflows
    module Code
      module Intent
        class End
          # The facts Prepare keeps about the Verification lines of outcome.md, and the messages that name what is wrong with them.
          module RecordFacts
            PULL_REQUEST_MISSING = "Add a line starting Pull request: to the Verification section of outcome.md and run plastic sync up."

            def self.verification_facts(context, verification)
              context[:merge_recorded], context[:map_recorded] = [verification.merged?, verification.architecture_map?]
              context[:merge_found] = merge_found(verification)
              context[:approval_found] = approval_found(verification)
              context[:awaiting_approval] = review_required?(context) && ready_for_approval?(context) && !verification.approved?
            end

            def self.merge_found(verification)
              found = verification.rejected("Merged")
              found ? "outcome.md says '#{found}', which is not a merge in the form 'Merged: <branch> into <base> at <commit or pull request>'. " : ""
            end

            def self.approval_found(verification)
              found = verification.rejected("Approved")
              found ? "outcome.md says '#{found}', which is not an approval in the form 'Approved: <person> on <YYYY-MM-DD>'; " : ""
            end

            def self.review_required?(context)
              Config.new(context.scope.plastic_home).choice(%w[review pull_request], default: "off", allowed: %w[required off]) == "required"
            end

            def self.pull_request_problems(check) = check.verification.pull_request? ? [] : [PULL_REQUEST_MISSING]

            def self.ready_for_approval?(context) = context.requirements.empty? && context.judged
          end
        end
      end
    end
  end
end
