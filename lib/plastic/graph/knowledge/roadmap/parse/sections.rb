# frozen_string_literal: true

require_relative "problems"
require_relative "goal"
require_relative "batches"
require_relative "edges"
require_relative "log"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The sections of a roadmap file by heading, and the result they make together.
          class Sections
            NAMES = { "Batches" => :batches, "Waves" => :batches, "Graph" => :graph, "Log" => :log, "Goal" => :goal }.freeze

            # The section of a heading that holds nothing to read.
            module Ignored
              module_function

              def line(_text, _number) = nil

              def finish = nil
            end

            def initialize(path)
              @problems = Problems.new(path)
              @parts = { goal: Goal.new, batches: Batches.new(@problems), graph: Edges.new(@problems), log: Log.new(@problems) }
            end

            def named(heading) = @parts.fetch(NAMES[heading], Ignored)

            def result(title)
              batches = @parts[:batches]
              Result.new(title:, goal: @parts[:goal].text, batches: batches.list, items: batches.items,
                edges: @parts[:graph].list, log: @parts[:log].list, problems: @problems.to_a)
            end
          end
        end
      end
    end
  end
end
