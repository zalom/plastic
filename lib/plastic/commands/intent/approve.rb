# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Writes the owner's go-ahead for an intent. `plastic auto` refuses an intent without it.
      class Approve < Routine
        intent_subject
        reads :knowledge
        writes :work
        prints :intent

        workflow :code_approve_intent, next: :noop
      end
    end
  end
end
