# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # One line of an intent's savepoint.md: the time it was written and what
    # happened. A line with no time keeps its text alone.
    Savepoint = Data.define(:intent_id, :position, :at, :text, :origin_id) do
      include Record

      # The time and the text of one line.
      def self.parse(line)
        found = line.match(Savepoint::TIMED)
        found ? found.captures : [nil, line]
      end

      def line = at ? "#{at}  #{text}" : text
    end
    Savepoint::TIMED = /\A(?<at>\d{4}-\d\d-\d\dT\S+)  (?<text>.*)\z/
  end
end
