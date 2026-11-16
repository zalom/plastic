# frozen_string_literal: true

require "time"
require_relative "../../../graph/backup/older_than"

module Plastic
  module Workflows
    module Code
      module Intent
        # Archives each unarchived intent that is older than a date, the way
        # `intent archive ID` archives one, and says what it did for each. An
        # intent that is not older than the date is passed over with no line.
        class ArchiveBefore
          OlderThan = Plastic::Graph::Backup::OlderThan

          def initialize(context)
            @work = context.work
            @intents = context.retrieval.unarchived_intents
            @cutoff = OlderThan.parse(context.older_than)
          end

          # One line for each intent archived or skipped; one line when none was.
          def lines
            found = intents.filter_map { |intent| line(intent) }
            found.empty? ? ["intent: nothing to archive"] : found
          end

          private

          attr_reader :work, :intents, :cutoff

          def line(intent)
            reason = skipped(intent)
            return "intent: #{intent.intent_id} skipped, #{reason}" if reason.is_a?(String)

            archive(intent) if reason
          end

          # True when the intent is to archive, a String when it is skipped, nil when passed over.
          def skipped(intent)
            return older?(intent.opened_at) if intent.status == "future"
            return closed(intent) if intent.closed?

            "it is #{intent.status}; end it first" if older?(intent.opened_at)
          end

          def closed(intent)
            return "it is #{intent.status} with no close date" unless moment(intent.closed_at)

            older?(intent.closed_at)
          end

          def archive(intent)
            ok, problem, = work.archive_intent(intent.intent_id)
            ok ? "intent: #{intent.intent_id} archived" : "intent: #{intent.intent_id} skipped, #{problem}"
          end

          def older?(stamp) = (time = moment(stamp)) && time < cutoff

          def moment(stamp) = (OlderThan.read(stamp) if stamp)
        end
      end
    end
  end
end
