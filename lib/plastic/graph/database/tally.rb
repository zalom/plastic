# frozen_string_literal: true

module Plastic
  module Graph
    class Database
      # The rows that one call wrote to a database, by table. The command run row is one row however often it is saved.
      class Tally
        def initialize(file)
          @file = file
          @counts = Hash.new(0)
        end

        def to_h = @counts

        def count(table, rows)
          before = @counts[table]
          @counts[table] = (table == RUNS) ? [before, rows].max : before + rows
        end

        # Runs the block; when it fails the counts go back to what they were.
        def keeping
          kept = @counts.dup
          yield
        rescue
          @counts.replace(kept)
          raise
        end

        # Whether this call wrote a row other than its command run.
        def wrote_rows? = @counts.keys.any? { |table| table != RUNS }

        # "1 intent and 1 work log line in work_graph.db", or nil when nothing but the command run was written.
        def phrase = wrote_rows? ? "#{Schema.phrase(@counts.except(RUNS))} in #{@file}" : nil

        def phrases = [phrase].compact
      end
    end
  end
end
