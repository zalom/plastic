# frozen_string_literal: true

module Plastic
  module Graph
    # The first line of an error, as the report of a migration says why a database stayed behind.
    module MigrationReason
      def self.of(error) = error.message.lines.first.to_s.strip
    end
  end
end
