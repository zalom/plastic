# frozen_string_literal: true

module Plastic
  module Graph
    # Writes a roadmap's own row, its batches and its items: a named plan,
    # held as rows instead of a hand-kept file.
    class RoadmapWriter
      # A batch's or an item's own words, carried as one value so a method
      # that builds a row takes one argument for them, not three.
      Fields = Data.define(:title, :goal, :done)

      LOOP_SQL = <<~SQL
        SELECT 1 WHERE EXISTS (
          WITH RECURSIVE reach(id) AS (
            SELECT "to" FROM roadmap_edges WHERE origin_id = :origin AND roadmap = :roadmap AND "from" = :to
            UNION
            SELECT roadmap_edges."to" FROM roadmap_edges JOIN reach ON roadmap_edges."from" = reach.id
            WHERE roadmap_edges.origin_id = :origin AND roadmap_edges.roadmap = :roadmap
          )
          SELECT 1 FROM reach WHERE id = :from
        )
      SQL

      def initialize(databases, retrieval, session: nil)
        @databases = databases
        @retrieval = retrieval
        @session = session
      end

      # Writes the batch's goal and done criteria, and the roadmap row the
      # first time it is named.
      def write_batch(slug, position, fields:)
        now = Plastic.now
        @databases.fetch(:work).transaction do |batch|
          batch.put(:roadmaps, roadmap_row(slug, now), statement: :upsert)
          batch.put(:batches, batch_row(slug, position, fields, now), statement: :upsert)
        end
        @retrieval.batches(slug).find { |row| row.position == position }
      end

      # Adds an item to batch N. Returns nil, nil when the batch is missing;
      # Returns [item, problem, kind]. kind is :failure or :refusal, nil on success.
      def add_item(slug, item, batch_position, fields:, after:)
        return [nil, "no batch #{batch_position} on roadmap #{slug}", :failure] unless batch?(slug, batch_position)

        missing = Array(after).find { |from| @retrieval.roadmap_items(slug).none? { |row| row.item == from } }
        return [nil, "no item #{missing} on roadmap #{slug}", :failure] if missing

        looped = Array(after).find { |from| loop?(slug, from, item) }
        return [nil, "an edge from #{looped} to #{item} would loop", :refusal] if looped

        write_item(slug, item, batch_position, fields, after)
      end

      def drop_item(slug, item)
        now = Plastic.now
        changed(:roadmap_items) do |batch|
          batch.write(:roadmap_items, "UPDATE roadmap_items SET mark = 'dropped', updated_at = :now " \
            "WHERE origin_id = :origin AND roadmap = :roadmap AND item = :item", now:, origin: origin_id, roadmap: slug, item:)
        end
      end

      def remove_roadmap_edge(slug, from, to)
        changed(:roadmap_edges) { |batch| batch.remove(:roadmap_edges, roadmap: slug, from:, to:) }
      end

      def add_log(slug, text)
        now = Plastic.now
        row = { roadmap: slug, position: next_log_position(slug), at: now, text:, session_id: @session }
        @databases.fetch(:work).transaction { |batch| batch.put(:roadmap_log, row, statement: :insert) }
        @retrieval.roadmap_log(slug).last
      end

      private

      def origin_id = @retrieval.origin_id

      def changed(table)
        database = @databases.fetch(:work)
        before = database.written[table.to_s]
        database.transaction { |batch| yield batch }
        database.written[table.to_s] > before
      end

      def batch?(slug, position) = @retrieval.batches(slug).any? { |row| row.position == position }

      def loop?(slug, from, to)
        !@databases.fetch(:work).row(LOOP_SQL, origin: origin_id, roadmap: slug, from:, to:).nil?
      end

      def write_item(slug, item, batch_position, fields, after)
        now = Plastic.now
        existing = @retrieval.roadmap_items(slug).any? { |row| row.item == item }
        @databases.fetch(:work).transaction do |batch|
          batch.put(:roadmap_items, item_row(slug, item, batch_position, fields, now), statement: :insert) unless existing
          Array(after).each { |from| batch.put(:roadmap_edges, { roadmap: slug, from:, to: item, kind: "after" }, statement: :insert) }
        end
        [@retrieval.roadmap_items(slug).find { |row| row.item == item }, nil, nil]
      end

      def roadmap_row(slug, now) = { slug:, title: slug, goal: nil, opened_at: now, updated_at: now }

      def batch_row(slug, position, fields, now)
        { roadmap: slug, position:, title: fields.title, goal: fields.goal, done: Array(fields.done).join("\n"), updated_at: now }
      end

      def item_row(slug, item, batch_position, fields, now)
        { roadmap: slug, item:, batch: batch_position, position: next_item_position(slug, batch_position),
          title: fields.title, goal: fields.goal, done: Array(fields.done).join("\n"), intent_id: nil, mark: nil,
          updated_at: now }
      end

      def next_item_position(slug, batch_position)
        positions = @retrieval.roadmap_items(slug).select { |row| row.batch == batch_position }.map(&:position)
        (positions.max || 0) + 1
      end

      def next_log_position(slug)
        (@retrieval.roadmap_log(slug).map(&:position).max || 0) + 1
      end
    end
  end
end
