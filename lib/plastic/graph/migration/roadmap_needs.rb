# frozen_string_literal: true

require_relative "../edge_walk"

module Plastic
  module Graph
    # Turns the item order of each roadmap into needs links between the intents its items opened. The migration of
    # this version dropped the roadmap tables after legacy.db kept them whole, so the step reads the kept edges and items.
    # A roadmap edge from item A to item B means B waits for A, so the link runs from B's intent to A's intent. An edge
    # that cannot become a link is skipped and counted: an item with no intent, an intent the store lacks, one intent
    # on both items, or a link that would close a loop. Docs: docs/contributing/MIGRATIONS.md.
    class RoadmapNeeds
      VERSION = "20261123120000"
      # The needs links written, and the roadmap edges skipped.
      Result = Data.define(:written, :skipped) do
        def line(slug)
          return if written.zero? && skipped.zero?

          text = "migrate: #{slug} wrote #{written} needs #{(written == 1) ? "link" : "links"} from the roadmap edges"
          skipped.zero? ? text : "#{text} and skipped #{skipped} roadmap #{(skipped == 1) ? "edge" : "edges"} that cannot be a link; legacy.db keeps every roadmap row"
        end
      end

      EDGES = <<~SQL
        SELECT t.intent_id AS from_ref, f.intent_id AS to_ref, e.origin_id AS origin_id, t.updated_at AS at
        FROM legacy."roadmap_edges_#{VERSION}" e
        JOIN legacy."roadmap_items_#{VERSION}" f ON f.roadmap = e.roadmap AND f.item = e."from" AND f.origin_id = e.origin_id
        JOIN legacy."roadmap_items_#{VERSION}" t ON t.roadmap = e.roadmap AND t.item = e."to" AND t.origin_id = e.origin_id
        ORDER BY e.roadmap, f.position, t.position
      SQL
      INTENT = "SELECT 1 FROM main.intents WHERE intent_id = ?"
      NEEDS = "SELECT from_ref, to_ref FROM main.links WHERE kind = 'needs'"
      INSERT = "INSERT OR IGNORE INTO main.links (from_ref, to_ref, kind, at, origin_id) VALUES (?, ?, 'needs', COALESCE(?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')), ?)"

      # `keep` is the keep of the data step; the step keeps nothing more, since the tables are in legacy.db whole.
      def initialize(connection, _root, _selection, keep:)
        @connection = connection
        @keep = keep
      end

      def call
        return Result.new(written: 0, skipped: 0) unless kept?

        pairs = @connection.read(NEEDS).map { |row| row.values_at("from_ref", "to_ref") }
        written = @connection.read(EDGES).count { |edge| link(edge, pairs) }
        Result.new(written:, skipped: @connection.read(EDGES).size - written)
      end

      private

      def kept? = !@connection.get_first_value("SELECT name FROM legacy.sqlite_master WHERE name = 'roadmap_edges_#{VERSION}'").nil?

      # Writes the link of one edge and answers whether it was written.
      def link(edge, pairs)
        from, to = edge.values_at("from_ref", "to_ref")
        return false unless usable?(from, to) && EdgeWalk.new(pairs).path(to, from).nil?

        @connection.execute(INSERT, [from, to, edge["at"], edge["origin_id"]])
        pairs << [from, to]
        true
      end

      def usable?(from, to) = from && to && from != to && [from, to].all? { |id| intent?(id) }

      def intent?(id) = !@connection.get_first_value(INTENT, [id]).nil?
    end
  end
end
