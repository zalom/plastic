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
      changes({})

      Shown = Data.define(:rows, :create, :open)

      def call
        projects = scope.projects
        shown = slugs.map { |slug| store_rows(slug, projects) }
        output.rows(shown.flat_map(&:rows))
        offer_next(shown)
      end

      def self.store_lines(retrieval, slug)
        needs = Plastic::Graph::Knowledge::IntentNeeds.new(retrieval)
        rows = Plastic::Graph::Knowledge::Intent::Listing.lines(retrieval.intents) { |intent| Plastic::Graph::Work::IntentRow.new(retrieval, intent, needs:).to_a.join(", ") }
        [["store:", slug], *rows.map { |name, text| ["#{name}:", text] }]
      end

      private

      def slugs = scope.requested? ? [scope.slug] : scope.known_slugs

      def offer_next(shown)
        create_store = shown.filter_map(&:create).first
        return output.next_step(create_store, because: "the project has no store") if create_store
        return output.next_step("plastic next", because: "pick the one to work on") if shown.any?(&:open)

        output.next_step(nil, because: "nothing is open; ask the person what to work on")
      end

      def store_rows(slug, projects)
        retrieval = Plastic::Graph.open(home: scope.plastic_home, store: slug).retrieval
        Shown.new(Status.store_lines(retrieval, slug), nil, retrieval.intents.any? { |intent| intent.open? || intent.unstarted? })
      rescue Plastic::Graph::MissingStore => error
        command = error.next_command(projects[slug])
        Shown.new([["store:", "#{slug} has no store folder; run #{command}"]], (command if scope.requested?), false)
      end
    end
  end
end
