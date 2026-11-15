# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../../graph"
require_relative "../../graph/work/node/counts"
require_relative "../../graph/knowledge/intent"
require_relative "../../graph/knowledge/intent/listing"
require_relative "../../graph/work/intent_row"

module Plastic
  module Workflows
    module Code
      # Every store under the Plastic home, its intents by group, and
      # their node counts by state. It opens each store itself.
      class Status < CodeWorkflow
        clear_declarations

        sets :create_store, :open_anywhere

        read "print each store with its intents" do |context|
          scope = context.scope
          slugs = scope.requested? ? [scope.slug] : scope.known_slugs
          shown = slugs.map { |slug| store_rows(scope, slug) }
          shown.each { |rows, _create, _open| rows.each { |label, value| context.row(label, value) } }
          context[:create_store] = shown.filter_map { |_rows, create, _open| create }.first
          context[:open_anywhere] = shown.any? { |_rows, _create, open| open }
        end

        outcome :create_store, if: ->(context) { context.create_store }, offers: "%{create_store}", because: "the project has no store"
        outcome :open, if: ->(context) { context.open_anywhere }, offers: "plastic next", because: "pick the one to work on"
        outcome :none, offers: nil, because: "nothing is open; ask the person what to work on"

        def self.store_rows(scope, slug)
          retrieval = Plastic::Graph.open(home: scope.plastic_home, store: slug).retrieval
          [show_store(retrieval, slug), nil, retrieval.intents.any?(&:open?)]
        rescue Plastic::Graph::MissingStore => error
          command = error.next_command(scope.projects[slug])
          [[["store:", "#{slug} has no store folder; run #{command}"]], (command if scope.requested?), false]
        end

        def self.show_store(retrieval, slug)
          rows = Plastic::Graph::Knowledge::Intent::Listing.lines(retrieval.intents) { |intent| Plastic::Graph::Work::IntentRow.new(retrieval, intent).to_a.join(", ") }
          [["store:", slug], *rows.map { |name, text| ["#{name}:", text] }]
        end
      end
    end
  end
end
