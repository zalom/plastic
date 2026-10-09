# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Builds the retrieval handoff manifest; the harness chooses its evidence.
    class IntentDiscover < Routine
      subject :intent_id, :terms, :source_projects
      argument :intent_id, label: "ID", text: "the owning intent"
      argument :terms, label: "TERMS", text: "literal search terms", rest: true
      option :source_projects, switch: "--source-project SLUG", text: "a source store", repeatable: true
      reads :knowledge
      writes :knowledge, :work

      workflow :code_discover_retrieval, next: :agent_external_agent_workflow
      workflow :agent_external_agent_workflow, next: :noop
    end
  end
end
