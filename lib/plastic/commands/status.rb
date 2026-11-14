# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../graph"
require_relative "../graph/work/node/counts"
require_relative "../graph/knowledge/intent"
require_relative "../graph/knowledge/intent/listing"
require_relative "../graph/work/intent_row"

module Plastic
  module Commands
    # Every store under the Plastic home, its intents by group, and
    # their node counts by state.
    class Status < CLI::Command
      reads :work

      def call
        projects = scope.projects
        shown = slugs.map { |slug| store_rows(slug, projects) }
        output.rows(shown.flat_map(&:first))
        offer_next(shown.filter_map(&:last).first)
      end

      private

      def slugs = scope.requested? ? [scope.slug] : scope.known_slugs

      def offer_next(create_store)
        return output.next_step("plastic next", because: "pick the one to work on") unless create_store

        output.next_step(create_store, because: "the project has no store")
      end

      def store_rows(slug, projects)
        [show_store(slug), nil]
      rescue Plastic::Graph::MissingStore => error
        command = error.next_command(projects[slug])
        [[["store:", "#{slug} has no store folder; run #{command}"]], (command if scope.requested?)]
      end

      def show_store(slug)
        retrieval = Plastic::Graph.open(home: scope.plastic_home, store: slug).retrieval
        rows = Plastic::Graph::Knowledge::Intent::Listing.lines(retrieval.intents) { |intent| Plastic::Graph::Work::IntentRow.new(retrieval, intent).to_a.join(", ") }
        [["store:", slug], *rows.map { |name, text| ["#{name}:", text] }]
      end
    end
  end
end
