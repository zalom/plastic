# frozen_string_literal: true

require_relative "../roadmap/parse"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Finds and parses the roadmap files of a legacy store.
        class Roadmaps
          def initialize(root)
            @root = root
          end

          def parse
            files.to_h do |path|
              [path, Roadmap::Parse.call(File.read(path, encoding: "UTF-8"), path: relative(path))]
            end
          end

          def relative(path) = path.delete_prefix("#{@root}/")

          def files = Dir.glob(File.join(@root, "roadmaps", "{,archived/}*.md")).reject { |path| path.end_with?(".savepoint.md") }.sort
        end
      end
    end
  end
end
