# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      # Exposes printed-file and backup reads through a retrieval graph.
      module StoreReads
        def printed = stored.printed
        def backups = stored.backups
      end
    end
  end
end
