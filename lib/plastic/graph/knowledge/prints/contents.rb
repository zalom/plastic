# frozen_string_literal: true

module Plastic
  module Graph
    module Prints
      # The rows of one intent or of the whole store, grouped by intent.
      Contents = Data.define(:groups)

      # The rows of each table, by intent.
      class Contents
        READERS = {
          documents: :itself, legacy_intents_data: :stored, work_log: :structure, nodes: :structure, runs: :structure, edges: :structure,
          approvals: :structure, verdicts: :structure, completions: :structure, contexts: :structure, discoveries: :structure, kept_files: :archives
        }.freeze
        TABLES = READERS.keys.freeze

        def self.read(retrieval, intent_id = nil)
          new(TABLES.to_h { |table| [table, retrieval.public_send(READERS.fetch(table)).public_send(table, intent_id).group_by(&:intent_id)] })
        end

        TABLES.each do |table|
          define_method(table) { |intent_id| groups.fetch(table).fetch(intent_id, []) }
        end
      end
    end
  end
end
