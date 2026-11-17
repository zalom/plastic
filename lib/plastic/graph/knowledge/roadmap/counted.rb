# frozen_string_literal: true

require_relative "../roadmap"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # One write to the store, and whether it changed a row: a count of the rows the database wrote went up.
        class Counted
          def initialize(database)
            @database = database
          end

          def changed
            counts = @database.written
            before = counts.dup
            @database.transaction { |batch| yield batch }
            counts != before
          end
        end
      end
    end
  end
end
