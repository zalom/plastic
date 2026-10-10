# frozen_string_literal: true

require_relative "output"

module Plastic
  class CLI
    # The answer as one JSON document, for `--json`. Raw text waits in the
    # document's output list, and an error ends the answer with an error row.
    class JsonOutput < Output
      def json? = true

      def raw(text) = tap { result.line(text) }

      private

      def print_answer(project)
        out.puts JSON.pretty_generate(result.document(project))
      end

      def error_document(message, kind, offer)
        row("error", { "kind" => kind, "message" => message })
        next_step(offer.command, because: offer.because)
        flush
      end
    end
  end
end
