# frozen_string_literal: true

require_relative "../roadmap"
require_relative "reach"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # What one roadmap holds now, read before a write decides: its batches, items and log, and whether an edge would loop.
        class Standing
          attr_reader :slug

          def initialize(databases, retrieval, slug)
            @databases = databases
            @retrieval = retrieval
            @slug = slug
          end

          def exists? = !@retrieval.roadmaps.find(@slug).nil?

          def batch(position) = @retrieval.roadmaps.batches(@slug).find { |row| row.position == position }

          def kept_words(position, fields) = fields.over(batch(position), "Batch #{position}")

          def new_item_position(name, batch_position) = holds?(name) ? nil : next_item_position(batch_position)

          def holds?(name) = !row_of(name).nil?

          def row_of(name) = items.find { |row| row.item == name }

          def next_item_position(batch_position)
            positions = items.select { |row| row.batch == batch_position }.map(&:position)
            (positions.max || 0) + 1
          end

          def next_log_position = (log.map(&:position).max || 0) + 1

          def last_log = log.last

          # The message and the kind (:failure or :refusal) of what stops an item from being added, nil when nothing does.
          def addition_problem(item, batch_position, needs)
            return ["no batch #{batch_position} on roadmap #{@slug}", :failure] unless batch(batch_position)

            missing_problem(needs) || loop_problem(item, needs)
          end

          private

          def missing_problem(needs)
            missing = needs.find { |from| !holds?(from) }
            ["no item #{missing} on roadmap #{@slug}", :failure] if missing
          end

          def loop_problem(item, needs)
            reach = Reach.new(@databases, @retrieval, @slug)
            from, path = needs.lazy.map { |need| [need, reach.loop_path(need, item)] }.find(&:last)
            ["an edge from #{from} to #{item} would loop: #{path.join(" -> ")}", :refusal] if path
          end

          def items = @retrieval.roadmaps.items(@slug)

          def log = @retrieval.roadmaps.log(@slug)
        end
      end
    end
  end
end
