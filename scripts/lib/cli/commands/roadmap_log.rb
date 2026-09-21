# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic roadmap log` - appends a savepoint line to a roadmap's ledger
# (`roadmap-savepoint append`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class RoadmapLog < Command
        USAGE_LINE = 'plastic roadmap log SLUG EVENT "TEXT" [--json]'

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "SLUG is required" if slug.to_s.empty?
          raise Usage, "EVENT is required" if event.to_s.empty?
          raise Usage, "TEXT is required" if text.to_s.empty?

          status = legacy.run("roadmap-savepoint", "append", "--roadmap", path, "--event", event, "--detail", text)
          raise Failure, "roadmap-savepoint exited #{status}" unless status.zero?

          @output.next_step("plastic roadmap show #{slug}", because: "the log line just landed on the state screen")
        end

        private

        def slug
          arguments[0]
        end

        def event
          arguments[1]
        end

        def text
          arguments[2]
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
