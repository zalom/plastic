# frozen_string_literal: true

require_relative "../roadmap"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # Reads a legacy roadmap file's text into the rows sync up
        # writes: a title and goal, the batches and items of its "## Batches" or
        # "## Waves" section, the "needs" edges of its "## Graph" section, and
        # the dated lines of its "## Log" section. Never raises: a line it
        # cannot read becomes a problem naming the file and the line.
        module Parse
          # A numbered batch heading of the roadmap.
          Batch = Data.define(:position, :title)
          # A checklist item of a batch, with its status.
          Item = Data.define(:item, :batch, :title, :status)
          # A dated line of the roadmap log.
          LogLine = Data.define(:at, :text)
          # Everything one roadmap file holds, with the lines it could not read.
          Result = Data.define(:title, :goal, :batches, :items, :edges, :log, :problems)

          TOKEN = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/

          module_function

          def call(text, path:)
            scan = Scan.new(path)
            text.each_line.map(&:chomp).each_with_index { |line, index| scan.line(line, index + 1) }
            scan.finish
            scan.result
          end
        end
      end
    end
  end
end

require_relative "parse/scan"
