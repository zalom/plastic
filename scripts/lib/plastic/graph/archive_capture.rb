# frozen_string_literal: true

module Plastic
  module Graph
    # Persists an intent directory snapshot before any archive removal begins.
    class ArchiveCapture
      def initialize(database, folder, origin_id, session:)
        @database = database
        @folder = folder
        @origin_id = origin_id
        @session = session
      end

      def capture(intent)
        entries = ArchiveTree.read(root(intent))
        raise ArchiveTree::Error, "intent #{intent.intent_id} has no directory to archive" if entries.empty?

        database.transaction do |batch|
          snapshot(intent.intent_id).capture(batch, entries)
          batch.put(:archives, archive_row(intent), statement: :upsert)
        end
      end

      private

      attr_reader :database, :folder, :origin_id, :session

      def archive_row(intent) = { intent_id: intent.intent_id, at: Plastic.now, restored_at: nil, session_id: session }

      def root(intent) = ArchiveLocation.root(folder, intent)

      def snapshot(intent_id) = ArchiveSnapshot.new(database, intent_id, origin_id)
    end
  end
end
