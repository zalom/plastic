# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Moves a future or parked intent to open, so that `plastic auto` and `plastic intent end` take it.
      class Open < Routine
        intent_subject
        writes :work
        prints :intent

        workflow :code_open_intent, next: :noop
      end
    end
  end
end
