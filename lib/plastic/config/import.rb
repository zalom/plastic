# frozen_string_literal: true

require "json"
require "yaml"

module Plastic
  class Config
    # Reads the settings of a config.yml and hands them, one row each, to the database that keeps them. A row already
    # there stays as it is, so a second import changes nothing.
    class Import
      INSERT = 'INSERT OR IGNORE INTO "settings"("scope", "key", "value") VALUES (:scope, :key, :value)'

      def initialize(path, into:)
        @path = path
        @into = into
      end

      def call = @into.transaction { |batch| add_rows(batch) }

      private

      def add_rows(batch) = rows.each { |row| batch.add(INSERT, **row) }

      def rows = scopes.flat_map { |scope, settings| scope_rows(scope, settings) }

      def scope_rows(scope, settings) = flat(settings).map { |key, value| { scope:, key:, value: JSON.generate(value) } }

      def document = File.file?(@path) ? YAML.safe_load_file(@path, aliases: true) : nil

      def data = document.is_a?(Hash) ? document : {}

      def scopes
        harnesses = data["harnesses"]
        [["global", data["global"]], *(harnesses.is_a?(Hash) ? harnesses.to_a : [])].select { |_scope, settings| settings.is_a?(Hash) }
      end

      def flat(hash, prefix = nil)
        hash.flat_map do |key, value|
          name = [prefix, key].compact.join(".")
          value.is_a?(Hash) ? flat(value, name) : [[name, value]]
        end
      end
    end
  end
end
