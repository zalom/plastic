# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic roadmap migrate` - writes a roadmap's `## Graph` section from the
# batch headings it already carries (`roadmap-graph migrate`, run through
# Legacy). This is the repair `plastic roadmap check` names when a roadmap has
# no graph, so the CLI can perform every repair it asks for.
module Plastic
  class CLI
    module Commands
      class RoadmapMigrate < Command
        USAGE_LINE = "plastic roadmap migrate SLUG [--dry-run] [--json]"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "SLUG is required" if slug.to_s.empty?
          raise Failure, "no roadmap #{slug} in #{File.basename(scope.roadmaps_dir)}" unless File.file?(path)

          arguments_for_script = ["migrate", path]
          arguments_for_script << "--dry-run" if options[:dry_run]
          status = legacy.run("roadmap-graph", *arguments_for_script)
          raise Failure, "roadmap-graph exited #{status}" unless status.zero?

          @output.next_step("plastic roadmap check #{slug}", because: "a written graph is what check reads")
        end

        private

        def switches(parser)
          parser.on("--dry-run") { @options[:dry_run] = true }
        end

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
