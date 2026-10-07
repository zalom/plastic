# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/schema"

module Plastic
  module Graph
    class DeclarationTest < Plastic::TestCase
      def test_a_line_gives_the_key_columns_and_each_typed_column
        key, columns = SchemaCatalog::Declaration.parse("store intent_id | store:kept intent_id:kept mode")

        assert_equal %i[store intent_id], key
        assert_equal({ store: :kept, intent_id: :kept, mode: :text }, columns)
      end

      def test_a_line_that_starts_with_the_bar_has_no_key
        key, columns = SchemaCatalog::Declaration.parse("| seq:serial row")

        assert_empty key
        assert_equal({ seq: :serial, row: :text }, columns)
      end
    end
  end
end
