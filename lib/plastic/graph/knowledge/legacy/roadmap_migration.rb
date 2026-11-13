# frozen_string_literal: true

require_relative "originals"
require_relative "roadmap_rows"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Moves parsed legacy roadmaps into the work graph and keeps their original bytes.
        class RoadmapMigration
          def initialize(graphs, root, counts)
            @graphs = graphs
            @root = root
            @counts = counts
          end

          def call(parsed) = parsed.each { |path, result| migrate(path, result) }

          private

          def migrate(path, result)
            slug = File.basename(path, ".md")
            original_bytes = File.binread(path)
            write(slug, path, result)
            Originals.new(@graphs.databases, @counts).keep_roadmap_original(@root, slug, original_bytes)
            count(result)
          end

          def write(slug, path, result)
            RoadmapRows.new(@graphs, slug, result).call(path.sub(/\.md\z/, ".savepoint.md"))
            @graphs.work.print_roadmap(slug)
          end

          def count(result)
            @counts[:roadmaps] += 1
            @counts[:roadmap_items] += result.items.size
          end
        end
      end
    end
  end
end
