# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      # Exposes printed-file and backup reads through a retrieval graph.
      module StoreReads
        def printed = stored.printed
        def backups = stored.backups
        def legacy_intents_data(intent_id = nil) = read(:legacy_intents_data, intent_id)
      end
    end
  end
end
