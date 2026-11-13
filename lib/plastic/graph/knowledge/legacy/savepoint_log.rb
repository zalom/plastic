# frozen_string_literal: true

require_relative "../roadmap/parse"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The `.savepoint.md` sibling of a roadmap: one line per event, its time stamp first.
        class SavepointLog
          def initialize(path)
            @path = path
          end

          def lines
            return [] unless File.exist?(@path)

            File.read(@path, encoding: "UTF-8").each_line.filter_map do |line|
              at, text = line.strip.split(/\s+/, 2)
              Roadmap::Parse::LogLine.new(at:, text: text.to_s.squeeze(" ")) if at
            end
          end
        end
      end
    end
  end
end
