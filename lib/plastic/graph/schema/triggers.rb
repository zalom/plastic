# frozen_string_literal: true

module Plastic
  module Graph
    # The triggers of a table, as the statements that make them.
    module SchemaTriggers
      def trigger_creates(table) = triggers_on(table).map(&:create)

      private

      def triggers_on(table) = triggers.values.select { |trigger| trigger.on == table }
    end
  end
end
