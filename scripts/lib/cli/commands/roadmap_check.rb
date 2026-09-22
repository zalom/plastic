# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic roadmap check` - the roadmap graph's batches, ready set and any
# cycle or dangling id (`roadmap-graph check`, run through Legacy).
#
# A roadmap with no `## Graph` section has nothing to check, and the script's
# own exit code says only that something failed. That case is named here, with
# the command that repairs it, so the reader never has to know which script ran.
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
          raise Failure, "no roadmap #{slug} in #{File.basename(scope.roadmaps_dir)}" unless File.file?(path)
          raise Failure, "#{slug} has no ## Graph section; plastic roadmap migrate #{slug} writes one from its batches" unless graph?

          status = legacy.run("roadmap-graph", "check", path)
          raise Failure, "roadmap-graph exited #{status}" unless status.zero?

          @output.next_step("plastic roadmap show #{slug}", because: "the graph just checked out clean")
        end

        private

        def graph?
          File.foreach(path).any? { |line| line.start_with?("## Graph") }
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
