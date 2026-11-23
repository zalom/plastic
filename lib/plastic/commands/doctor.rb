# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    class Doctor < Routine
      opens_no_store
      reads :work, :retrieval
      writes :retrieval
      keeps_no_command_run
      changes(retrieval: "The search index is rebuilt from the documents when it is out of step with them")

      option :harness_name, switch: "--harness NAME", text: "the harness to check, such as claude-code; the one the call runs in when left out"

      workflow :code_check_health, next: :noop
    end
  end
end
