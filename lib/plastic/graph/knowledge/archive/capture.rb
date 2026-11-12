# frozen_string_literal: true

require_relative "../archive"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Persists an intent directory snapshot before any archive removal begins.
        class Capture
          def initialize(database, folder, origin_id, session:)
            @database = database
            @folder = folder
            @origin_id = origin_id
            @session = session
          end

          def capture(intent)
            entries = Tree.read(root(intent))
            raise Tree::Error, "intent #{intent.intent_id} has no directory to archive" if entries.empty?

            store(intent, entries)
          end

          private

          attr_reader :database, :folder, :origin_id, :session

          def store(intent, entries)
            database.transaction do |batch|
              snapshot(intent.intent_id).capture(batch, entries)
              batch.put(:archives, archive_row(intent), statement: :upsert)
            end
          end

          def archive_row(intent) = { intent_id: intent.intent_id, at: Plastic.now, restored_at: nil, session_id: session }

          def root(intent) = Location.root(folder, intent)

          def snapshot(intent_id) = Snapshot.new(database, intent_id, origin_id)
        end
      end
    end
  end
end
