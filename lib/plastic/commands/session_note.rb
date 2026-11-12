# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Writes the one prose line of a session: what the routine runs cannot say.
    class SessionNote < Routine
      argument :text, label: "TEXT", text: "the note, in words", rest: true
      writes :work
      workflow :code_write_note, next: :noop
    end
  end
end
