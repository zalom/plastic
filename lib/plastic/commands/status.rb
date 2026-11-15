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
        offer_next(shown.filter_map { |_rows, create, _open| create }.first, shown.any? { |_rows, _create, open| open })
      end

      private

      def slugs = scope.requested? ? [scope.slug] : scope.known_slugs

      def offer_next(create_store, open_anywhere)
        return output.next_step(create_store, because: "the project has no store") if create_store
        return output.next_step("plastic next", because: "pick the one to work on") if open_anywhere

        output.next_step(nil, because: "nothing is open; ask the person what to work on")
      end

      def store_rows(slug, projects)
        retrieval = Plastic::Graph.open(home: scope.plastic_home, store: slug).retrieval
        [show_store(retrieval, slug), nil, retrieval.intents.any?(&:open?)]
      rescue Plastic::Graph::MissingStore => error
        command = error.next_command(projects[slug])
        [[["store:", "#{slug} has no store folder; run #{command}"]], (command if scope.requested?), false]
      end

      def show_store(retrieval, slug)
        rows = Plastic::Graph::Knowledge::Intent::Listing.lines(retrieval.intents) { |intent| Plastic::Graph::Work::IntentRow.new(retrieval, intent).to_a.join(", ") }
        [["store:", slug], *rows.map { |name, text| ["#{name}:", text] }]
      end
    end
  end
end
