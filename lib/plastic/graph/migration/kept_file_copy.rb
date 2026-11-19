# frozen_string_literal: true

require "digest"
require "fileutils"

module Plastic
  module Graph
    # Finds a verified copy of the bytes of a kept file outside sqlar: the file on disk, or the archive of its intent.
    # A file that is gone from disk is printed back first. The answer is nil when a verified copy exists, or else the
    # reason the row has to stay.
    class KeptFileCopy
      ARCHIVED = "SELECT 1 FROM main.archives WHERE intent_id = :intent_id AND restored_at IS NULL"
      ENTRIES = <<~SQL
        SELECT e.data FROM main.archive_entries e JOIN main.archives a ON a.intent_id = e.intent_id AND a.origin_id = e.origin_id
        WHERE a.restored_at IS NULL AND e.kind = 'file' AND e.intent_id = :intent_id AND e.path = :path
      SQL

      def initialize(connection, root)
        @connection = connection
        @root = root
      end

      def missing(file)
        return archive_reason(file) if archived?(file)

        path = file.path(@root)
        return print_back(file, path) unless File.exist?(path)

        "the file on disk differs" unless File.file?(path) && Digest::SHA256.file(path).hexdigest == file.digest
      end

      private

      def archived?(file) = !file.intent_id.nil? && !@connection.read(ARCHIVED, intent_id: file.intent_id).empty?

      def archive_reason(file)
        held = @connection.read(ENTRIES, intent_id: file.intent_id, path: file.in_intent).any? { |entry| Digest::SHA256.hexdigest(entry.fetch("data").to_s) == file.digest }
        "intent #{file.intent_id} is archived and its archive holds no copy of it" unless held
      end

      def print_back(file, path)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, file.bytes)
        nil
      end
    end
  end
end
