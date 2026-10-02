# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"
require_relative "../graph/node_counts"

module Plastic
  module Commands
    # Every store under the Plastic home, its open and active intents, and
    # their node counts by state.
    class Status < CLI::Command
      reads :work

      def call
        scope.known_slugs.each { |slug| print_store(slug) }
        output.next_step("plastic next", because: "pick the one to work on")
      end

      private

      def print_store(slug)
        retrieval = Graph.open(home: scope.plastic_home, store: slug).retrieval
        output.row("store:", slug)
        retrieval.intents.select(&:open?).each { |intent| print_intent(retrieval, intent) }
      end

      def print_intent(retrieval, intent) = output.row(*Graph::IntentRow.new(retrieval, intent).to_a)
    end
  end
end
