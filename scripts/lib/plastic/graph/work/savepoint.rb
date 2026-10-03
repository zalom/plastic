# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One line of an intent's savepoint.md: the time it was written and what
      # happened. A line with no time keeps its text alone. `session_id` names
      # the session that wrote the line, nil for a new line imported from a file.
      Savepoint = Data.define(:intent_id, :position, :at, :text, :origin_id, :session_id)

      # How a line reads and prints.
      class Savepoint
        include Record

        TIMED = /\A(?<at>\d{4}-\d\d-\d\dT\S+)  (?<text>.*)\z/

        # The time and the text of one line.
        def self.parse(line)
          found = line.match(TIMED)
          found ? found.captures : [nil, line]
        end

        def line = at ? "#{at}  #{text}" : text
      end
    end
  end
end
