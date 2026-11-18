# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Writes a future intent: its row and its first rows, and prints its folder and
      # store/index.json in the same call. intent start or intent auto starts it.
      class New < Routine
        subject :title
        argument :title, label: "TITLE", text: "what the intent is for, in words", rest: true
        option :parent_id, switch: "--parent ID", text: "the intent this one is a child of"
        option :ref, switch: "--ref REF", text: "a ticket, a link, or another intent as ID-ORIGIN"
        option :after, switch: "--after ID", text: "an intent this one grows out of, linked as source"
        option :kind, switch: "--kind KIND", text: "the kind of work", default: "work"
        writes :work, :knowledge
        prints :intent

        workflow :code_write_intent, next: :noop
      end
    end
  end
end
