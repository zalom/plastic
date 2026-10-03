# frozen_string_literal: true

require_relative "archive_snapshot"
require_relative "archive_location"
require_relative "archive_capture"
require_relative "archive_completion"
require_relative "archive_guard"
require_relative "archive_operation"
require_relative "archive_printed_cleanup"
require_relative "archive_restore"
require_relative "archive_snapshot_index"

module Plastic
  module Graph
    # Commits a full directory snapshot before removal, and restores that
    # snapshot before clearing the archived marker.
    class ArchiveWriter
      def initialize(databases, retrieval, folder, session: nil)
        @databases = databases
        @retrieval = retrieval
        @folder = folder
        @session = session
      end

      # Returns [ok, problem, kind]; kind is :failure or :refusal, nil on success.
      def archive(intent_id)
        archive_operation.call(intent_id)
      rescue ArchiveTree::Error, SystemCallError => error
        [false, error.message, :failure]
      end

      # Returns [ok, problem, kind]; kind is :failure, nil on success.
      def restore(intent_id)
        restore_operation.call(intent_id)
      rescue ArchiveTree::Error, SystemCallError => error
        [false, error.message, :failure]
      end

      private

      def origin_id = @retrieval.origin_id

      def snapshot(intent_id) = ArchiveSnapshot.new(@databases.fetch(:work), intent_id, origin_id)

      def remove_printed(dir)
        ArchivePrintedCleanup.new(@databases, @retrieval).remove(dir)
      end

      def capture = ArchiveCapture.new(@databases.fetch(:work), @folder, origin_id, session: @session)

      def guard = ArchiveGuard.new(@retrieval)

      def archive_operation = ArchiveOperation.new(@retrieval, guard, capture, completion)

      def completion
        ArchiveCompletion.new(ArchiveSnapshotIndex.new(@databases.fetch(:knowledge), origin_id), @folder,
          snapshot: method(:snapshot), remove_printed: method(:remove_printed))
      end

      def restore_operation = ArchiveRestore.new(@databases.fetch(:work), @retrieval, @folder, snapshot: method(:snapshot))
    end
  end
end
