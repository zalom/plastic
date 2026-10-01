# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Arms delivery: takes the lock and sets the intent active.
    class AutoStart < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent"
      writes :work
      workflow :code_start_auto, next: :noop
    end
  end
end
