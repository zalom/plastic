# frozen_string_literal: true

require "json"
require_relative "../graph"

module Plastic
  class Config
    # The settings rows of the machine database. A database that is missing,
    # busy, or not at the version of the settings table reads as no rows: a
    # broken home never stops a hook or a command.
    class Rows
      FILE = "plastic.db"

      def initialize(plastic_home)
        @home = plastic_home
        @path = File.join(plastic_home, FILE)
      end

      # The settings of one scope as a nested hash.
      def scope(name)
        read("SELECT key, value FROM settings WHERE scope = :scope ORDER BY key", scope: name).each_with_object({}) do |(key, json), tree|
          *parents, leaf = key.split(".")
          parents.reduce(tree) { |node, part| node[part] = node[part].is_a?(Hash) ? node[part] : {} }[leaf] = JSON.parse(json)
        end
      end

      # The hash recorded when the file was last printed, or nil.
      def printed(file) = read("SELECT sha256 FROM printed_files WHERE path = :path", path: file).dig(0, 0)

      # Every scope that holds a row.
      def scopes = read("SELECT DISTINCT scope FROM settings").flatten

      private

      def read(sql, **binds)
        return [] unless File.file?(@path)

        Graph::Database.open_local(@home).fetch(:local).rows(sql, **binds).map(&:values)
      rescue
        []
      end
    end
  end
end
