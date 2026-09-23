# frozen_string_literal: true

require_relative "../command"
require_relative "../frontier"
require_relative "../scope"

# `plastic next` - one line saying what to pick up, then the step to take and
# the rule that chose it. `--why` adds the roadmap, its frontier batch, and
# what is dispatchable, in flight and blocked.
module Plastic
  class CLI
    module Commands
      class Next < Command
        USAGE_LINE = "plastic next [--why] [--project SLUG] [--json]"

        def call
          active_id = scope.active_ids.first unless frontier.roadmap
          @output.row("next work", active_id ? "#{active_id}  in #{scope.slug}" : frontier.summary)
          detail if options[:why]
          if active_id
            @output.next_step("plastic intent show #{active_id}", because: "#{active_id} is the first active intent in #{scope.slug}")
          else
            @output.next_step(frontier.next_step, because: frontier.because)
          end
        rescue RoadmapSavepoint::MissingGroupingHeading => e
          raise Failure, e.message
        end

        private

        def switches(parser)
          parser.on("--why") { @options[:why] = true }
          parser.on("--project SLUG") { |slug| @options[:project] = slug }
        end

        def detail
          @output.row("roadmap", frontier.roadmap || Frontier::NONE)
          @output.row("frontier", frontier.heading || Frontier::NONE)
          @output.row("dispatchable", listed(frontier.dispatchable_ids))
          @output.row("in flight", listed(frontier.in_flight_ids))
          @output.row("blocked", listed(frontier.blocked_ids))
        end

        def listed(ids)
          ids.empty? ? Frontier::NONE : ids.join(", ")
        end

        def frontier
          @frontier ||= Frontier.new(scope)
        end
      end
    end
  end
end
