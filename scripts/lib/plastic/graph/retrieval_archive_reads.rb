# frozen_string_literal: true

module Plastic
  module Graph
    # Exposes archive and retained-file reads through a retrieval graph.
    module RetrievalArchiveReads
      def archive_of(intent_id) = archives.archive_of(intent_id)
      def archived?(intent_id) = archives.archived?(intent_id)
      def archived_reference?(reference) = archived?(fetch_reference(reference).fetch(:intent_id))
      def kept_files(intent_id = nil) = read(:kept_files, intent_id)
      def kept_file_data(name) = stored.kept_file_data(name)
    end
  end
end
