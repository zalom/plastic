# frozen_string_literal: true

require "shellwords"
require_relative "agent_workflow"

module Plastic
  module Workflows
    # Gives an external agent deterministic retrieval commands without selecting evidence.
    class ExternalAgentWorkflow < ::Plastic::AgentWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :handoff_text, :context_command, :context_complete

      step "select retrieved evidence", done: ->(context) { context.context_complete }, say: "%{handoff_text}"
      outcome :handoff, offers: "%{context_command}", because: "an external agent must select the evidence"
      outcome :done, offers: nil, because: "the retrieval context was submitted"

      class << self
        def retrieval_handoff(intent_id:, project:, search:)
          { "search" => search, "evidence" => "plastic document get REF",
            "context" => Shellwords.join(["plastic", "intent", "context", intent_id, "--from", "FILE", "--project", project]) }
        end

        def search_command(terms, sources)
          Shellwords.join(["plastic", "search", terms, *sources.flat_map { |source| ["--source-project", source] }])
        end
      end
    end
  end

  ExternalAgentWorkflow = Workflows::ExternalAgentWorkflow
end
