# frozen_string_literal: true

module Plastic
  module Graph
    # Exposes printed-file and backup reads through a retrieval graph.
    module RetrievalStoreReads
      def printed = stored.printed
      def backups = stored.backups
      def backup_flag(backup) = stored.backup_flag(backup)
    end
  end
end
