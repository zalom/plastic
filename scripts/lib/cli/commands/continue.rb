# frozen_string_literal: true

require_relative "../command"
require_relative "../frontier"
require_relative "../scope"

# `plastic continue` - where one project stands and what runs next: the store it
# uses, the intents it has open, its liveliest roadmap and that roadmap's
# frontier, then the step to take and the rule behind it.
#
# With no roadmap the first active intent answers instead, so a project that
# never grew a roadmap still gets a next step.
module Plastic
  class CLI
    module Commands
      class Continue < Command
        USAGE_LINE = "plastic continue [--project SLUG] [--json]"

        def call
          @output.row("project", scope.slug)
          @output.row("root", scope.root)
          @output.row("active", active)
          @output.row("roadmap", roadmap)
          command, because = decision
          @output.next_step(command, because: because)
        rescue RoadmapSavepoint::MissingGroupingHeading => e
          raise Failure, e.message
        end

        private

        def switches(parser)
          parser.on("--project SLUG") { |slug| @options[:project] = slug }
        end

        def active
          scope.active_entries.map { |id, title| "#{id}  #{title}" }
        end

        def roadmap
          return Frontier::NONE unless frontier.roadmap

          "#{frontier.roadmap}  frontier #{frontier.heading}"
        end

        def decision
          return [frontier.next_step, frontier.because] if frontier.roadmap

          id = scope.active_ids.first
          return [plan_for(id), "#{id} is the first active intent in #{scope.slug}"] if id

          ["plastic help", "#{scope.slug} has no active work and no roadmap"]
        end

        def plan_for(id)
          dir = scope.intent_dir(id)
          dir ? "plastic intent show #{id}" : "plastic status"
        end

        def frontier
          @frontier ||= Frontier.new(scope)
        end
      end
    end
  end
end
