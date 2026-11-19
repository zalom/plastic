# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../database"
require_relative "../knowledge/sync_selection"

module Plastic
  module Graph
    # Keeps in sqlar only the files that a sync of this machine reads. Every other row goes, and a row whose file is gone
    # from the store folder is printed back to its path first, unless its intent is archived, because the archive holds
    # that file. It runs in the transaction of the migration, so a refusal takes the migration back with it.
    class KeptFilesCleanup
      # A row names a path outside the store folder.
      class Refused < Database::Error; end

      ROWS = "SELECT name, data, intent_id FROM main.sqlar ORDER BY name"
      ARCHIVED = "SELECT DISTINCT intent_id FROM main.archives WHERE restored_at IS NULL"
      DELETE = "DELETE FROM main.sqlar WHERE name IN (SELECT value FROM json_each(?))"

      # One row of sqlar: the path it names in the store folder, its bytes and its intent.
      Row = Data.define(:name, :data, :intent_id) do
        def self.from(row) = new(name: row.fetch("name"), data: row.fetch("data"), intent_id: row.fetch("intent_id"))

        def path(root) = File.expand_path(name, root)

        def inside?(root) = path(root).start_with?(File.join(root, ""))

        # Writes the bytes to the path, unless a file is there or the archive of its intent holds it.
        def print_back(root, archived)
          file = path(root)
          return if File.exist?(file) || archived.include?(intent_id)

          FileUtils.mkdir_p(File.dirname(file))
          File.binwrite(file, data.to_s)
        end
      end

      def initialize(connection, root, selection)
        @connection = connection
        @root = File.expand_path(root)
        @selection = selection
      end

      # Answers the number of rows it removed.
      def call
        rows = removed
        refuse_outside(rows)
        rows.each { |row| row.print_back(@root, archived) }
        @connection.execute(DELETE, [JSON.generate(rows.map(&:name))])
        rows.size
      end

      private

      def removed = @connection.read(ROWS).map { |row| Row.from(row) }.reject { |row| kept?(row.name) }

      def kept?(name) = name[Knowledge::SyncSelection::INTENT_FILE, 1]&.then { |rel| @selection.read?(rel) }

      def refuse_outside(rows)
        outside = rows.find { |row| !row.inside?(@root) }
        raise Refused, "the kept file #{outside.name} leads outside the store folder" if outside
      end

      def archived = (@archived ||= @connection.read(ARCHIVED).map { |row| row.fetch("intent_id") })
    end
  end
end
