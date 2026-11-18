# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Intent
      # Parks one intent in progress with the reason it waits; intent start resumes it.
      class Park < Routine
        intent_subject
        argument :reason, label: "REASON", text: "why the work waits", rest: true
        writes :work
        prints :intent

        workflow :code_park_intent, next: :noop
      end
    end
  end
end
