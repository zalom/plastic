# frozen_string_literal: true

require_relative "../archive"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Indexes an archive snapshot and removes the matching live directory.
        class Completion
          def initialize(snapshot_index, folder, snapshot:, remove_printed:)
            @snapshot_index = snapshot_index
            @folder = folder
            @snapshot = snapshot
            @remove_printed = remove_printed
          end

          def call(intent)
            index_snapshot(intent)
            snapshot.call(intent.intent_id).remove(root(intent))
            remove_printed.call(intent.dir)
          end

          private

          attr_reader :folder, :remove_printed, :snapshot, :snapshot_index

          def index_snapshot(intent)
            intent_id = intent.intent_id
            snapshot_index.index(intent_id, snapshot.call(intent_id).entries)
          end

          def root(intent) = Location.root(folder, intent)
        end
      end
    end
  end
end
