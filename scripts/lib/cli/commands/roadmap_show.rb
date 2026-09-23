# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"
require_relative "../../roadmap_graph"

# `plastic roadmap show` - a roadmap's state screen (`report-screen roadmap
# FILE state`, run through Legacy). SLUG is required: `plastic roadmap next`
# is the command that picks one when the caller has none in mind.
module Plastic
  class CLI
    module Commands
      class RoadmapShow < Command
        USAGE_LINE = "plastic roadmap show SLUG [--json]"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "SLUG is required" if slug.to_s.empty?

          status = legacy.run("report-screen", "roadmap", path, "state")
          raise Failure, "report-screen exited #{status}" unless status.zero?

          problems = graph_problems
          problems.each { |problem| @output.row("warning", problem) }
          if problems.empty?
            @output.next_step("plastic roadmap log #{slug} EVENT \"TEXT\"", because: "a savepoint is how this state screen keeps moving")
          else
            @output.next_step("plastic roadmap check #{slug}", because: "the graph has problems the state screen cannot show")
          end
        end

        private

        # A cycle or a graph id no batch lists (acceptance N8). The state screen
        # cannot show either, so they are named under it.
        def graph_problems
          return [] unless File.file?(path)

          result = RoadmapGraph.analyze(path)
          problems = []
          problems << "cyclic graph: #{result[:cycle].join(" > ")}" if result[:cycle]
          dangling = Array(result[:dangling])
          problems << "graph names #{dangling.join(", ")}, no batch entry" unless dangling.empty?
          problems
        end

        def slug
          arguments.first
        end

        def path
          File.join(scope.roadmaps_dir, "#{slug}.md")
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner, output: @output, json: options[:json])
        end
      end
    end
  end
end
