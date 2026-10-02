# frozen_string_literal: true

require_relative "../cli/command"

module Plastic
  module Commands
    # Builds the retrieval handoff manifest; the harness chooses its evidence.
    class IntentDiscover < CLI::Command
      argument :intent_id, label: "ID", text: "the owning intent"
      argument :terms, label: "TERMS", text: "literal search terms", rest: true
      reads :knowledge

      def call
        output.row("discovery", manifest)
        output.next_step("none", because: "the retrieval candidates were recorded")
      end

      private

      def manifest
        { intent_id: parsed.fetch(:intent_id), query: parsed.fetch(:terms), scope: [scope.slug], candidates: [] }
      end
    end
  end
end
