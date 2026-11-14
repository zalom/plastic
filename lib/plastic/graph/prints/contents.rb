# frozen_string_literal: true

module Plastic
  module Graph
    module Prints
      # The rows of one intent or of the whole store, grouped by intent.
      Contents = Data.define(:groups)

      # The rows of each table, by intent.
      class Contents
        TABLES = %i[documents legacy_intents_data savepoints nodes edges approvals verdicts completions contexts discoveries kept_files].freeze

        def self.read(retrieval, intent_id = nil)
          new(TABLES.to_h { |table| [table, retrieval.public_send(table, intent_id).group_by(&:intent_id)] })
        end

        TABLES.each do |table|
          define_method(table) { |intent_id| groups.fetch(table).fetch(intent_id, []) }
        end
      end
    end
  end
end
