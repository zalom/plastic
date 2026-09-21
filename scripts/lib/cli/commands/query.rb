# frozen_string_literal: true

require_relative "../command"
require_relative "../../search_index"

module Plastic
  class CLI
    module Commands
      class Query < Command
        USAGE_LINE = "plastic query SQL [--json]"

        def call
          raise Usage, "SQL is missing" if arguments.empty?
          raise Failure, "no index at #{database}; run plastic index" unless File.file?(database)

          rows = Sqlite.call(database, arguments.join(" "), readonly: true)
          rows.each_with_index { |row, index| @output.row((index + 1).to_s, row.map { |key, value| "#{key}=#{value}" }.join("  ")) }
          @output.next_step("none", because: "the rows are the whole answer; the database is opened read-only")
        rescue Sqlite::Error => e
          raise Failure, e.message
        end

        private

        def database
          SearchIndex.path(scope.plastic_home)
        end
      end
    end
  end
end
