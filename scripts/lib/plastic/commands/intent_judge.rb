# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints the judge steps for an intent, or records the verdict of the next review round.
    class IntentJudge < Routine
      VERDICTS = %w[accept revise].freeze

      intent_subject
      option :verdict, switch: "--verdict accept|revise", text: "the verdict of this review round"
      option :findings, switch: "--findings TEXT", text: "what the review showed; required with --verdict"
      writes :work

      workflow :code_prepare_judge do
        on :recording, next: :code_record_verdict
        on :judging, next: :agent_judge_intent
        on :accepted, next: :noop
      end
      workflow :code_record_verdict, next: :noop
      workflow :agent_judge_intent, next: :noop

      def call(*)
        verdict_problem&.then { |text| raise CLI::Command::Usage, text }

        super
      end

      private

      def verdict_problem
        return "--verdict takes accept or revise" if parsed[:verdict] && !VERDICTS.include?(parsed[:verdict])

        "--verdict and --findings come together" if parsed[:verdict].to_s.empty? != parsed[:findings].to_s.strip.empty?
      end
    end
  end
end
