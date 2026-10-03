# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Persists the agent's selected evidence without judging its relevance.
    class IntentContext < Routine
      argument :intent_id, label: "ID", text: "the owning intent"
      option :from, switch: "--from FILE", text: "JSON evidence selection with facts, interpretations, gaps and rulings"
      reads :knowledge
      writes :knowledge

      workflow :code_check_context_owner do
        on :submit, next: :code_submit_context
        on :read, next: :code_read_context
      end
      workflow :code_read_context, next: :noop
      workflow :code_submit_context, next: :noop
    end
  end
end
