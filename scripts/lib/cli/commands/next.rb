# encoding: UTF-8
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

        private

        def options(parser)
          parser.on("--why") { @options[:why] = true }
          parser.on("--project SLUG") { |slug| @options[:project] = slug }
        end

        def call
          @output.row("next work", frontier.summary)
          detail if @options[:why]
          @output.next_step(frontier.next_step, because: frontier.because)
        rescue RoadmapSavepoint::MissingGroupingHeading => e
          raise Failure, e.message
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
