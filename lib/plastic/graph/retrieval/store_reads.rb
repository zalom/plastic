# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      # Exposes printed-file reads through a retrieval graph.
      module StoreReads
        def printed = stored.printed
        def legacy_intents_data(intent_id = nil) = read(:legacy_intents_data, intent_id)
      end
    end
  end
end
