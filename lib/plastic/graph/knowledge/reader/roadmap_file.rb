# frozen_string_literal: true

require_relative "../../../invalid"
require_relative "../roadmap"
require_relative "../roadmap/form"
require_relative "roadmap_records"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # A roadmap file in form 2 read back into the rows of its roadmap: the file name is the slug,
        # and the labeled lines carry every value. The lines that only show a state or a need are skipped.
        class RoadmapFile
          Form = Roadmap::Form
          NOUNS = { head: "a head", batches: "a batch", items: "an item", edges: "an edge", log: "a log line" }.freeze
          REQUIRED = { head: %i[title], batches: %i[position], items: %i[item position], edges: %i[from to kind], log: %i[position text] }.freeze

          def self.form?(text) = Form.form?(text.dup.force_encoding(Encoding::UTF_8))

          def initialize(slug, text)
            @slug = slug
            text = text.dup.force_encoding(Encoding::UTF_8)
            raise Invalid, "roadmaps/#{slug}.md is in an older form that this release does not read" unless Form.form?(text)

            @records = RoadmapRecords.new(text.lines(chomp: true).drop(1))
            check
          end

          # The read replaces the rows of this slug that this home's origin wrote, so a line cannot be read twice.
          def apply(batch, now)
            remove_rows(batch)
            batch.put(:roadmaps, header.merge(updated_at: now))
            { batches: :batches, items: :roadmap_items, edges: :roadmap_edges, log: :roadmap_log }.each { |kind, table| batch.put_all(table, rows(kind, now)) }
          end

          private

          def remove_rows(batch)
            %i[batches roadmap_items roadmap_edges roadmap_log].each { |table| batch.remove(table, roadmap: @slug) }
            batch.remove(:roadmaps, slug: @slug)
          end

          def check
            REQUIRED.each { |kind, names| check_kind(kind, names) }
            named = @records.head["slug"]
            raise Invalid, "roadmaps/#{@slug}.md names the slug #{named}, not #{@slug}" if named && named != @slug
          end

          def check_kind(kind, names) = @records.of(kind).each { |record| missing(kind, record, names) }

          def missing(kind, record, names)
            gone = names.select { |name| record[name.to_s].to_s.empty? }
            raise Invalid, "roadmaps/#{@slug}.md has #{NOUNS.fetch(kind)} record with no #{gone.join(", ")}" if gone.any?
          end

          def header
            title, goal, opened_at = @records.head.values_at("title", "goal", "opened_at")
            { slug: @slug, title:, goal: RoadmapRecords.blank(goal), opened_at: RoadmapRecords.blank(opened_at) }
          end

          def rows(kind, now)
            stamp = %i[batches items].include?(kind) ? { updated_at: now } : {}
            @records.of(kind).map { |record| send(:"#{kind}_row", record).merge(stamp) }
          end

          def batches_row(record) = base(record, "goal").merge(title: record["title"].to_s, done: record["done"].to_s, position: number(record, "position"))

          def items_row(record)
            base(record, "item", "title", "goal", "intent_id", "mark").merge(done: record["done"].to_s, batch: number(record, "batch"), position: number(record, "position"))
          end

          def edges_row(record) = base(record, "from", "to", "kind")

          def log_row(record) = base(record, "at", "text", "session_id").merge(position: number(record, "position"))

          def base(record, *names) = names.to_h { |name| [name.to_sym, RoadmapRecords.blank(record[name])] }.merge(roadmap: @slug)

          def number(record, name)
            Integer(record[name], 10)
          rescue ArgumentError, TypeError
            raise Invalid, "roadmaps/#{@slug}.md holds a #{name} that is not a number"
          end
        end
      end
    end
  end
end
