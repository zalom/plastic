# frozen_string_literal: true

module Plastic
  module Workflows
    module Code
      # The workflows of the commands that work on the migrations of one store.
      module Migration
        # The rows a migration event moved, by table: "1 row of document_revisions and 2 rows of sqlar".
        def self.counted(moved)
          parts = moved.map { |table, count| "#{count} #{(count == 1) ? "row" : "rows"} of #{table}" }
          return "no rows" if parts.empty?

          [parts[0...-1].join(", "), parts.last].reject(&:empty?).join(" and ")
        end
      end
    end
  end
end
