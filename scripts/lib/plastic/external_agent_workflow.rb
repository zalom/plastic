# frozen_string_literal: true

require "shellwords"

module Plastic
  # Gives an external agent deterministic retrieval commands without selecting evidence.
  class ExternalAgentWorkflow < AgentWorkflow
    [facts, steps, outcomes].each(&:clear)

    sets :handoff_text

    step "select retrieved evidence and provide architecture context", done: ->(context) { context.handoff_text.nil? }, say: "%{handoff_text}"
    outcome :handoff, offers: nil, because: "an external agent must select evidence and provide architecture context"
    outcome :done, offers: nil, because: "the retrieval context was submitted"

    class << self
      def retrieval_handoff(intent_id:, terms:, sources:, project:)
        { "search" => search_command(terms, sources), "evidence" => "plastic document get REF",
          "architecture" => "external architecture provider records coverage and limitations",
          "context" => Shellwords.join(["plastic", "intent", "context", intent_id, "--from", "FILE", "--project", project]) }
      end

      private

      def search_command(terms, sources)
        Shellwords.join(["plastic", "search", terms, *sources.flat_map { |source| ["--source-project", source] }])
      end
    end
  end
end
