# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic roadmap check` - the roadmap graph's batches, ready set and any
# cycle or dangling id (`roadmap-graph check`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class RoadmapCheck < Command
        USAGE_LINE = "plastic roadmap check SLUG [--json]"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "SLUG is required" if slug.to_s.empty?

          status = legacy.run("roadmap-graph", "check", path)
          raise Failure, "roadmap-graph exited #{status}" unless status.zero?

          @output.next_step("plastic roadmap show #{slug}", because: "the graph just checked out clean")
        end

        private

        def slug
          arguments.first
        end

        def path
          File.join(scope.roadmaps_dir, "#{slug}.md")
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
