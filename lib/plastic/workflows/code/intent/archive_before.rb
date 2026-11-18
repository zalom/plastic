# frozen_string_literal: true

require "forwardable"
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

          # An intent set against the cutoff date: the reason it is skipped, true
          # when it is to be archived, nil when it is passed over.
          Candidate = Data.define(:intent, :cutoff) do
            extend Forwardable

            def_delegators :intent, :status, :opened_at, :closed_at, :closed?
            def_delegator :intent, :intent_id, :id

            def self.moment(stamp) = (OlderThan.read(stamp) if stamp)

            def line(work)
              reason = verdict
              return "intent: #{id} skipped, #{reason}" if reason.is_a?(String)

              archived(work) if reason
            end

            private

            def verdict
              return settled if closed? && status != "future"

              stale = older?(opened_at)
              (status == "future") ? stale : ("it is #{status}; end it first" if stale)
            end

            def archived(work)
              ok, problem, = work.archive_intent(id)
              ok ? "intent: #{id} archived" : "intent: #{id} skipped, #{problem}"
            end

            def settled
              return "it is #{status} with no close date" unless self.class.moment(closed_at)

              older?(closed_at)
            end

            def older?(stamp) = (time = self.class.moment(stamp)) && time < cutoff
          end

          def initialize(context)
            @context = context
          end

          # One line for each intent archived or skipped; one line when none was.
          def lines
            found = candidates.filter_map { |candidate| candidate.line(context.work) }
            found.empty? ? ["intent: nothing to archive"] : found
          end

          private

          attr_reader :context

          def candidates
            cutoff = OlderThan.parse(context.older_than)
            context.retrieval.unarchived_intents.map { |intent| Candidate.new(intent, cutoff) }
          end
        end
      end
    end
  end
end
