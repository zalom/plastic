# frozen_string_literal: true

require "json"
require_relative "../database"
require_relative "../knowledge/sync_selection"
require_relative "kept_file"
require_relative "kept_file_copy"

module Plastic
  module Graph
    # Keeps in sqlar only the files that a sync of this machine reads. Every other row goes only when a verified copy of
    # its bytes is elsewhere: the file on disk or the archive of its intent, with the same SHA-256. A row whose file is
    # gone is printed back to its path first. Any other row stays and is reported. It runs in the transaction of the
    # migration, so a refusal takes the migration back with it.
    class KeptFilesCleanup
      # A row names a path outside the store folder.
      class Refused < Database::Error; end

      # The number of rows it removed, and each row it kept for want of a verified copy, with the reason.
      Result = Data.define(:removed, :kept) do
        def line(slug)
          return if kept.empty?

          "migrate: #{slug} keeps these rows in sqlar, as no verified copy of them is elsewhere: #{kept.map { |name, reason| "#{name} (#{reason})" }.join(", ")}"
        end
      end

      ROWS = "SELECT name, data, intent_id, origin_id FROM main.sqlar ORDER BY name"
      DELETE = "DELETE FROM main.sqlar WHERE name IN (SELECT value FROM json_each(?))"

      def initialize(connection, root, selection)
        @connection = connection
        @root = File.expand_path(root)
        @selection = selection
      end

      def call
        files = removed
        refuse_outside(files)
        copies = KeptFileCopy.new(@connection, @root)
        gone, kept = files.to_h { |file| [file.name, copies.missing(file)] }.partition { |_name, reason| reason.nil? }
        @connection.execute(DELETE, [JSON.generate(gone.map(&:first))])
        Result.new(removed: gone.size, kept: kept.to_h)
      end

      private

      def removed = @connection.read(ROWS).map { |row| KeptFile.from(row) }.reject { |file| kept?(file.in_intent) }

      def kept?(rel) = rel && @selection.read?(rel)

      def refuse_outside(files)
        outside = files.find { |file| !file.inside?(@root) }
        raise Refused, "the kept file #{outside.name} leads outside the store folder" if outside
      end
    end
  end
end
