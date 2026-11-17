# frozen_string_literal: true

require_relative "../archive"
require_relative "marking"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Persists an intent directory snapshot before any archive removal begins.
        class Capture
          def initialize(database, folder, origin_id, marking)
            @database = database
            @folder = folder
            @origin_id = origin_id
            @marking = marking
          end

          def capture(intent)
            entries = Tree.read(root(intent))
            raise Tree::Error, "intent #{intent.intent_id} has no directory to archive" if entries.empty?

            store(intent, entries)
          end

          private

          attr_reader :database, :folder, :marking, :origin_id

          def store(intent, entries)
            database.transaction do |batch|
              snapshot(intent.intent_id).capture(batch, entries)
              batch.put(:archives, marking.row(intent), statement: :upsert)
            end
          end

          def root(intent) = Location.root(folder, intent)

          def snapshot(intent_id) = Snapshot.new(database, intent_id, origin_id)
        end
      end
    end
  end
end
