# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    # Reads stored archive and backup records without loading file bytes unless needed.
    class RetrievalStoreRead
      def initialize(databases)
        @databases = databases
      end

      def kept_file_data(name)
        row = databases.fetch(:references).row("SELECT hex(data) AS data FROM sqlar WHERE name = :name", name:)
        [row.fetch("data")].pack("H*")
      end

      def printed
        Schema.store.flat_map { |key| databases.fetch(key).rows("SELECT path, sha256 FROM printed") }
          .to_h { |row| row.values_at("path", "sha256") }
      end

      def backups
        databases.fetch(:home).rows("SELECT * FROM backups ORDER BY at").map { |row| Backup.from_h(row) }
      end

      def backup_flag(backup)
        path = File.join(home_dir, "backups", backup.name)
        return "missing" unless File.exist?(path)

        (Digest::SHA256.file(path).hexdigest == backup.sha256) ? nil : "changed"
      end

      private

      attr_reader :databases

      def home_dir = File.dirname(databases.fetch(:home).path)
    end
  end
end
