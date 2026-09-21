# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic roadmap next` - the roadmap most worth continuing right now
# (`roadmap-next --which`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class RoadmapNext < Command
        USAGE_LINE = "plastic roadmap next [--json]"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          status = legacy.run("roadmap-next", "--roadmaps-dir", scope.roadmaps_dir, "--which")
          raise Failure, "roadmap-next exited #{status}" unless status.zero?

          @output.next_step("plastic roadmap show SLUG", because: "the winner it just named is the slug that command wants")
        end

        private

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
