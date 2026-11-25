# frozen_string_literal: true

require_relative "../../routine"
require_relative "../../graph/knowledge/ruling/numbers"

module Plastic
  module Commands
    module Intent
      # Writes one owner decision against an intent, numbered one after the last. --adds writes an addition to a decision
      # under its next number, such as D1.1, and --rewrites replaces the text of a decision and removes its additions.
      class Rule < Routine
        intent_subject
        argument :text, label: "TEXT", text: "the decision, in the owner's words"
        option :adds, switch: "--adds DECISION_ID", text: "a decision this one adds to, such as `D1`; it takes the next number under it, such as `D1.1`"
        option :rewrites, switch: "--rewrites DECISION_ID", text: "a decision whose text this one replaces; the additions of that decision are removed"
        reads :work
        writes :knowledge
        prints :intent

        def call
          named = parsed.values_at(:adds, :rewrites).compact
          raise Usage, "--adds and --rewrites exclude each other" if named.size > 1
          raise Usage, "--adds and --rewrites name a whole decision, such as D1" unless named.all? { |id| Plastic::Graph::Knowledge::Ruling::Numbers.whole?(id) }

          super
        end

        workflow :code_add_ruling, next: :noop
      end
    end
  end
end
