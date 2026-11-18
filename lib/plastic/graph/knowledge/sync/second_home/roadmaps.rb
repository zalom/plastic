# frozen_string_literal: true

require_relative "../../reader/roadmap_file"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class SecondHome
          OLDER_FORM = "is in an older form that this release does not read"

          # The roadmap files that have no roadmap row in this home.
          class Roadmaps
            def initialize(folder, retrieval)
              @folder = folder
              @retrieval = retrieval
            end

            def paths = files.select { |path| problem(path).nil? }

            def problems = files.to_h { |path| [path, problem(path)] }.compact

            private

            def files = @folder.roadmap_files.reject { |path| @retrieval.roadmaps.find(File.basename(path, ".md")) }

            def problem(path)
              slug = File.basename(path, ".md")
              text = @folder.read(path)
              return "roadmaps/#{slug}.md #{OLDER_FORM}" unless Reader::RoadmapFile.form?(text)

              Reader::RoadmapFile.new(slug, text)
              nil
            rescue Invalid => error
              error.message
            end
          end
        end
      end
    end
  end
end
