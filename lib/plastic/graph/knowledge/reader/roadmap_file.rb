# frozen_string_literal: true

require_relative "../../../invalid"
require_relative "../roadmap"
require_relative "../roadmap/form"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # A roadmap file in form 2 read back into the rows of its roadmap: the file name is the slug,
        # and the labeled lines carry every value. The lines that only show a state or a need are skipped.
        class RoadmapFile
          Form = Roadmap::Form
          RECORD_STARTS = { "- edge" => :edges, "- log" => :log }.freeze
          NOUNS = { head: "a head", batches: "a batch", items: "an item", edges: "an edge", log: "a log line" }.freeze
          REQUIRED = { head: %i[title], batches: %i[position title], items: %i[item position], edges: %i[from to kind], log: %i[position text] }.freeze

          def self.form?(text) = Form.form?(text.dup.force_encoding(Encoding::UTF_8))

          def initialize(slug, text)
            @slug = slug
            text = text.dup.force_encoding(Encoding::UTF_8)
            raise Invalid, "roadmaps/#{slug}.md is in an older form that this release does not read" unless Form.form?(text)

            @records = Hash.new { |hash, key| hash[key] = [] }
            @head = {}
            parse(text.lines(chomp: true).drop(1))
            check
          end

          def database = :work

          # The read replaces the rows of this slug that this home's origin wrote, so a line cannot be read twice.
          def apply(batch)
            remove_rows(batch)
            batch.put(:roadmaps, header)
            { batches: :batches, items: :roadmap_items, edges: :roadmap_edges, log: :roadmap_log }.each { |kind, table| batch.put_all(table, rows(kind)) }
          end

          private

          def remove_rows(batch)
            %i[batches roadmap_items roadmap_edges roadmap_log].each { |table| batch.remove(table, roadmap: @slug) }
            batch.remove(:roadmaps, slug: @slug)
          end

          def parse(lines)
            @section = :head
            @target = @head
            lines.each { |line| read_line(line) }
          end

          def read_line(line)
            return heading(line) if line.start_with?("## ")
            return start(:items) if @section == :batches && line.start_with?("- [")
            return start(@section) if RECORD_STARTS[line] == @section

            labeled(line)
          end

          def heading(line)
            batch = line[/\A## Batch (\d+)(?::|\z)/, 1]
            @section = batch ? :batches : line.delete_prefix("## ").downcase.to_sym
            @section = :edges if @section == :graph
            start(:batches, position: batch) if batch
          end

          def start(kind, **fields)
            @target = fields.transform_keys(&:to_s).merge("batch" => @records[:batches].last&.fetch("position", nil))
            @records[kind] << @target
          end

          def labeled(line)
            found = Form::LABELED.match(line)
            @target[found[1]] = Form.unescape(found[2].to_s) if found
          end

          def check
            REQUIRED.each { |kind, names| Array((kind == :head) ? [@head] : @records[kind]).each { |record| missing(kind, record, names) } }
            raise Invalid, "roadmaps/#{@slug}.md names the slug #{@head["slug"]}, not #{@slug}" if @head["slug"] && @head["slug"] != @slug
          end

          def missing(kind, record, names)
            gone = names.reject { |name| record[name.to_s] && !record[name.to_s].empty? }
            raise Invalid, "roadmaps/#{@slug}.md has #{NOUNS.fetch(kind)} record with no #{gone.join(", ")}" if gone.any?
          end

          def header = { slug: @slug, title: @head["title"], goal: blank(@head["goal"]), opened_at: blank(@head["opened_at"]), updated_at: Plastic.now }

          def rows(kind) = @records[kind].map { |record| send(:"#{kind}_row", record) }

          def batches_row(record) = base(record, "title", "goal").merge(done: record["done"].to_s, position: number(record, "position"), updated_at: Plastic.now)

          def items_row(record)
            base(record, "item", "title", "goal", "intent_id", "mark").merge(done: record["done"].to_s, batch: number(record, "batch"), position: number(record, "position"),
              updated_at: Plastic.now)
          end

          def edges_row(record) = base(record, "from", "to", "kind")

          def log_row(record) = base(record, "at", "text", "session_id").merge(position: number(record, "position"))

          def base(record, *names) = names.to_h { |name| [name.to_sym, blank(record[name])] }.merge(roadmap: @slug)

          def blank(value) = (value && value.empty?) ? nil : value

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
