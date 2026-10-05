# frozen_string_literal: true

require_relative "../archive"
require_relative "snapshot"
require_relative "location"
require_relative "capture"
require_relative "completion"
require_relative "guard"
require_relative "operation"
require_relative "printed_cleanup"
require_relative "restore"
require_relative "snapshot_index"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Commits a full directory snapshot before removal, and restores that
        # snapshot before clearing the archived marker.
        class Writer
          def initialize(databases, retrieval, folder, session: nil, files: FileSystem.new)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
            @collaborators = { session:, files: }
          end

          # Returns [ok, problem, kind]; kind is :failure or :refusal, nil on success.
          def archive(intent_id) = self.class.attempt { archive_operation.call(intent_id) }

          # Returns [ok, problem, kind]; kind is :failure, nil on success.
          def restore(intent_id) = self.class.attempt { restore_operation.call(intent_id) }

          def self.attempt
            yield
          rescue Tree::Error, SystemCallError => error
            [false, error.message, :failure]
          end

          private

          def origin_id = @retrieval.origin_id

          def snapshot(intent_id) = Snapshot.new(@databases.fetch(:work), intent_id, origin_id, files: @collaborators[:files])

          def remove_printed(dir) = PrintedCleanup.new(@databases, @retrieval).remove(dir)

          def capture = Capture.new(@databases.fetch(:work), @folder, origin_id, session: @collaborators[:session])

          def guard = Guard.new(@retrieval)

          def archive_operation = Operation.new(@retrieval, guard, capture, completion)

          def completion
            Completion.new(SnapshotIndex.new(@databases.fetch(:knowledge), origin_id), @folder,
              snapshot: method(:snapshot), remove_printed: method(:remove_printed))
          end

          def restore_operation = Restore.new(@databases.fetch(:work), @retrieval, @folder, snapshot: method(:snapshot))
        end
      end
    end
  end
end
