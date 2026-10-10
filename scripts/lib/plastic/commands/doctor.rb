# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    class Doctor < Routine
      opens_no_store

      option :harness_name, switch: "--harness NAME", text: "the harness to check, such as claude-code; the one the call runs in when left out"

      workflow :code_check_health, next: :noop
    end
  end
end
