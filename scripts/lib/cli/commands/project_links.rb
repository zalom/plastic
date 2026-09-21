# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic project links` - projects every store's `## Links` sections from
# frontmatter (`project-links`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class ProjectLinks < Command
        USAGE_LINE = "plastic project links [--dry-run] [--json]"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          status = legacy.run("project-links", "--plastic-home", scope.plastic_home, *dry_run_flag)
          raise Failure, "project-links exited #{status}" unless status.zero?

          @output.next_step("plastic status", because: "the Links sections just rebuilt across every store")
        end

        private

        def switches(parser)
          parser.on("--dry-run") { @options[:dry_run] = true }
        end

        def dry_run_flag
          options[:dry_run] ? ["--dry-run"] : []
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
