# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

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

          @output.next_step("plastic roadmap log #{slug} EVENT \"TEXT\"", because: "a savepoint is how this state screen keeps moving")
        end

        private

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
