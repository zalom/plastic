# frozen_string_literal: true

module Plastic
  module Graph
    # Restores a stored snapshot and clears its archive marker after publication.
    class ArchiveRestore
      def initialize(database, retrieval, folder, snapshot:)
        @database = database
        @retrieval = retrieval
        @folder = folder
        @snapshot = snapshot
      end

      def call(intent_id)
        return unavailable(intent_id) unless retrieval.archived?(intent_id)

        restore(intent_id)
        [true, nil, nil]
      end

      private

      attr_reader :database, :folder, :retrieval, :snapshot

      def unavailable(intent_id) = [false, "intent #{intent_id} is not archived", :failure]

      def restore(intent_id)
        intent = retrieval.intent(intent_id)
        snapshot.call(intent_id).restore(ArchiveLocation.root(folder, intent))
        mark_restored(intent_id)
      end

      def mark_restored(intent_id)
        database.transaction do |batch|
          batch.write(:archives, "UPDATE archives SET restored_at = :now WHERE origin_id = :origin AND intent_id = :intent_id",
            now: Plastic.now, origin: retrieval.origin_id, intent_id:)
        end
      end
    end
  end
end
