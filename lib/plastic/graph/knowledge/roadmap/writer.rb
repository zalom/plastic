# frozen_string_literal: true

require "forwardable"
require_relative "../roadmap"
require_relative "item_adder"
require_relative "item_marks"
require_relative "counted"
require_relative "rows"
require_relative "standing"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # Writes a roadmap's own row, its batches and its log: a named plan,
        # held as rows instead of a hand-kept file.
        class Writer
          extend Forwardable

          Fields = Roadmap::Fields

          def_delegators :adder, :add_item
          def_delegators :marks, :open_item, :drop_item

          def initialize(databases, retrieval, clock:, session: nil)
            @databases = databases
            @retrieval = retrieval
            @session = session
            @clock = clock
          end

          def create_roadmap(slug, title:, goal:)
            row = Rows.new(slug, stamp).roadmap.merge(title:, goal:)
            store.transaction { |batch| batch.put(:roadmaps, row, statement: :insert) }
            @retrieval.roadmaps.find(slug)
          end

          # Writes the batch's goal and done criteria, and the roadmap row the
          # first time it is named. A field left out keeps the batch's word for
          # it, and a new batch with no title is called "Batch N".
          def write_batch(slug, position, fields:)
            standing = standing(slug)
            rows = Rows.new(slug, stamp)
            kept = standing.kept_words(position, fields)
            store.transaction do |batch|
              batch.put(:roadmaps, rows.roadmap, statement: :insert) unless standing.exists?
              batch.put(:batches, rows.batch(position, kept), statement: :upsert)
            end
            standing.batch(position)
          end

          def remove_roadmap_edge(slug, from, to)
            Counted.new(store).changed { |batch| batch.remove(:roadmap_edges, roadmap: slug, from:, to:) }
          end

          def add_log(slug, text)
            standing = standing(slug)
            row = Rows.new(slug, stamp).log(standing.next_log_position, text, @session)
            store.transaction { |batch| batch.put(:roadmap_log, row, statement: :insert) }
            standing.last_log
          end

          private

          def adder = ItemAdder.new(@databases, @retrieval, clock: @clock)

          def marks = ItemMarks.new(@databases, @retrieval, clock: @clock)

          def store = @databases.fetch(:store)

          def stamp = Plastic.timestamp(@clock.now)

          def standing(slug) = Standing.new(@databases, @retrieval, slug)
        end
      end
    end
  end
end
