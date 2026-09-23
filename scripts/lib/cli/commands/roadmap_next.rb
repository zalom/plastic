# frozen_string_literal: true

require "json"
require_relative "../command"
require_relative "../legacy"

# `plastic roadmap next` - the roadmap most worth continuing right now
# (`roadmap-next --which`, run through Legacy). The script speaks JSON, so this
# command renders it as a screen and leaves the document to `--json`, the way
# every other command reads.
module Plastic
  class CLI
    module Commands
      class RoadmapNext < Command
        USAGE_LINE = "plastic roadmap next [--json]"
        AFTER = "plastic roadmap show SLUG"
        BECAUSE = "the winner it just named is the slug that command wants"
        TIED = "the roadmaps tie; the first is shown, and any of them may be picked"

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          report = parse(*legacy.capture("roadmap-next", "--roadmaps-dir", scope.roadmaps_dir, "--which"))
          screen(report)
          @output.next_step(after(report), because: (report["state"] == "tie") ? TIED : BECAUSE)
        end

        private

        def parse(text, status)
          raise Failure, "roadmap-next exited #{status}" unless status.zero?

          JSON.parse(text)
        rescue JSON::ParserError
          raise Failure, "roadmap-next did not print a report"
        end

        def after(report)
          slug = (report["roadmap"] || tied(report).first).to_s
          slug.empty? ? AFTER : AFTER.sub("SLUG", slug)
        end

        # roadmap-next --which reports a tie as state "tie" with "tie" false and
        # each candidate as an object; older reports carried plain names.
        def tied(report)
          Array(report["tie_candidates"]).map { |candidate| candidate.is_a?(Hash) ? candidate["roadmap"] : candidate }
        end

        def screen(report)
          @output.row("state", report["state"])
          @output.row("roadmap", report["roadmap"] || "none")
          @output.row("wave", report["frontier_wave"]) unless report["frontier_wave"].to_s.empty?
          @output.row("next", queue(report["dispatchable_queue"]))
          @output.row("delivering", entries(report["in_flight"]))
          @output.row("blocked", entries(report["blocked"]))
          @output.row("tie", tied(report).join(", ")) if report["tie"] || report["state"] == "tie"
        end

        def queue(list)
          rows = entries(list)
          rows.empty? ? "none" : rows
        end

        def entries(list)
          Array(list).map { |entry| [entry["id"], entry["status"], entry["wave"]].compact.join("  ") }
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner, output: @output, json: options[:json])
        end
      end
    end
  end
end
