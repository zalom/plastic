# frozen_string_literal: true

require_relative "../command"
require_relative "../../search_index"

module Plastic
  class CLI
    module Commands
      class Index < Command
        USAGE_LINE = "plastic index [--json]"

        def call
          count = SearchIndex.build(scope.plastic_home)
          @output.row("indexed", "#{count} files")
          @output.row("database", SearchIndex.path(scope.plastic_home))
          @output.next_step("plastic search TERMS", because: "the index is whole and new; it is rebuilt, never updated")
        rescue Sqlite::Error => e
          raise Failure, e.message
        end
      end
    end
  end
end
