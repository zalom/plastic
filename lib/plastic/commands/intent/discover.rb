# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Builds the retrieval handoff manifest; the harness chooses its evidence.
      class Discover < Routine
        subject :intent_id, :terms, :source_projects
        argument :intent_id, label: "ID", text: "the owning intent"
        argument :terms, label: "TERMS", text: "the words of a question, ranked by BM25; quote a phrase to keep it whole", rest: true
        option :source_projects, switch: "--source-project SLUG", text: "a source store", repeatable: true
        reads :knowledge, :retrieval
        writes :knowledge, :work
        prints :intent

        workflow :code_discover_retrieval, next: :agent_external_agent_workflow
        workflow :agent_external_agent_workflow, next: :noop
      end
    end
  end
end
