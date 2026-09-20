# encoding: UTF-8
# frozen_string_literal: true

require_relative "../roadmap_queue"

# Plastic::CLI::Frontier (intent 363) - the one reader of "what comes next" in a
# scope. `plastic next` prints it as a line and `plastic continue` prints it
# inside a project block, so the rule that picks the work is stated once rather
# than twice.
#
# It reads RoadmapQueue's queue mode: the liveliest roadmap, its frontier batch,
# the entries that can be dispatched, the entries in flight and the blocked
# ones. With no roadmap at all it answers the "none" state rather than raising,
# and a roadmap with no grouping heading raises through to the command, which
# fails loudly instead of parsing it as zero entries.
module Plastic
  class CLI
    class Frontier
      NONE = "none"

      def initialize(scope)
        @scope = scope
      end

      def state
        payload["state"]
      end

      def roadmap
        payload["roadmap"]
      end

      def heading
        payload["frontier_wave"]
      end

      def dispatchable_ids
        ids(payload["dispatchable_queue"])
      end

      def in_flight_ids
        ids(payload["in_flight"])
      end

      def blocked_ids
        ids(payload["blocked"])
      end

      def id
        (dispatchable_ids + in_flight_ids).first
      end

      def summary
        return NONE unless id

        "#{id}  in #{heading}"
      end

      def because
        return "#{@scope.slug} has no roadmap" if state == NONE
        return "every entry on #{roadmap} is delivered" if id.nil?

        "#{id} is first on the frontier of #{roadmap}"
      end

      def next_step
        return "plastic status" unless id

        plan = @scope.intent_dir(id)
        plan ? "read #{File.join(plan, "plan.md")}" : "plastic status"
      end

      private

      def payload
        @payload ||= RoadmapQueue.new(roadmaps_dir: @scope.roadmaps_dir,
                                      index_path: @scope.index_path).queue
      end

      def ids(entries)
        Array(entries).map { |entry| entry["id"] }
      end
    end
  end
end
