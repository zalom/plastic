# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"
require_relative "../graph/work/node/counts"
require_relative "../graph/work/intent_row"

module Plastic
  module Commands
    # Every store under the Plastic home, its open and active intents, and
    # their node counts by state.
    class Status < CLI::Command
      reads :work

      def call
        output.rows(slugs.flat_map { |slug| store_rows(slug) })
        output.next_step("plastic next", because: "pick the one to work on")
      end

      private

      def slugs = scope.requested? ? [scope.slug] : scope.known_slugs

      def store_rows(slug)
        show_store(slug)
      rescue Graph::MissingStore => error
        [["store:", "#{slug} has no store folder; run #{error.next_command}"]]
      end

      def show_store(slug)
        retrieval = Graph.open(home: scope.plastic_home, store: slug).retrieval
        [["store:", slug], *retrieval.intents.select(&:open?).map { |intent| Graph::Work::IntentRow.new(retrieval, intent).to_a }]
      end
    end
  end
end
