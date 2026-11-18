# frozen_string_literal: true

require "digest"
require "json"

module Plastic
  class Config
    # The settings rows of the machine database. A database that is missing,
    # busy, or not at the version of the settings table reads as no rows: a
    # broken home never stops a hook or a command.
    class Rows
      UPSERT = 'INSERT OR REPLACE INTO "settings"("scope", "key", "value") VALUES (:scope, :key, :value)'
      RECORD = 'INSERT OR REPLACE INTO "printed"("path", "sha256", "at", "origin_id") VALUES (:path, :sha256, :at, :origin_id)'

      def initialize(database)
        @database = database
      end

      # The settings of one scope as a nested hash.
      def scope(name)
        read("SELECT key, value FROM settings WHERE scope = :scope ORDER BY key", scope: name).each_with_object({}) do |(key, json), tree|
          Rows.insert(tree, key, JSON.parse(json))
        end
      end

      def self.insert(tree, key, value)
        *parents, leaf = key.split(".")
        parents.reduce(tree) { |node, part| descend(node, part) }[leaf] = value
      end

      def self.descend(node, part)
        child = node[part]
        child.is_a?(Hash) ? child : (node[part] = {})
      end

      def set(scope, key, value) = @database.transaction { |batch| batch.add(UPSERT, scope:, key:, value: JSON.generate(value)) }

      def record_print(path, text, at)
        @database.transaction { |batch| batch.add(RECORD, path:, sha256: Digest::SHA256.hexdigest(text), at:, origin_id: @database.origin_id) }
      end

      # The hash recorded when the file was last printed, or nil.
      def printed(file) = read("SELECT sha256 FROM printed WHERE path = :path", path: file).dig(0, 0)

      # Every scope that holds a row.
      def scopes = read("SELECT DISTINCT scope FROM settings").flatten

      private

      def read(sql, **binds)
        @database.rows(sql, **binds).map(&:values)
      end
    end
  end
end
