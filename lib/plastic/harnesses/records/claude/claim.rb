# frozen_string_literal: true

module Plastic
  module Harnesses
    module Records
      class Claude
        # The turn of one transcript that ran a claim command. The turn is written before the command executes, so before the
        # start Plastic stores for the run.
        class Claim
          # [file, window] of the file whose claim is nearest the run, nil when no file ran the claim.
          def self.nearest(files, run, pattern)
            found = files.filter_map { |file| (time = new(Jsonl.read(file) || [], run, pattern).at) && [time, file] }
            time, file = pick(found, run)
            [file, time..run.end] if file
          end

          # The latest claim at or before the start of the run, else the earliest inside it.
          def self.pick(found, run) = found.select { |time, _| time <= run.begin }.max_by(&:first) || found.min_by(&:first)

          def initialize(entries, run, pattern)
            @entries = entries
            @run = run
            @pattern = pattern
          end

          # The time of the claim turn of this file the run starts from, nil when no turn up to the end of the run ran the claim.
          def at
            times = @entries.select { |entry| claim?(entry) }.map { |entry| Jsonl.time(entry) }.sort
            self.class.pick(times.map { |time| [time, nil] }, @run)&.first
          end

          private

          def claim?(entry)
            Transcript.turn?(entry) && Jsonl.time(entry) <= @run.end && Transcript.commands(entry).any? { |command| command.match?(@pattern) }
          end
        end
      end
    end
  end
end
