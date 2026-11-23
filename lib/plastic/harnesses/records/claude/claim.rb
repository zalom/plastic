# frozen_string_literal: true

module Plastic
  module Harnesses
    module Records
      class Claude
        # The turn of one transcript that ran a claim command. The turn is written before the command executes, so before the
        # start Plastic stores for the run.
        class Claim
          def initialize(entries, run)
            @entries = entries
            @run = run
          end

          # The time of the latest claim turn at or before the start of the run, else the first one inside the run, nil when no
          # turn up to the end of the run ran the claim.
          def at(pattern)
            times = times(pattern)
            times.reverse.find { |time| time <= @run.begin } || times.first
          end

          private

          def times(pattern)
            turns = @entries.select { |entry| Transcript.turn?(entry) }.map { |entry| [Jsonl.time(entry), entry] }
            turns.select { |time, entry| time <= @run.end && ran?(entry, pattern) }.map(&:first).sort
          end

          def ran?(entry, pattern) = Transcript.commands(entry).any? { |command| command.match?(pattern) }
        end
      end
    end
  end
end
