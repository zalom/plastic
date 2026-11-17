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

      def call
        @into.transaction { |batch| rows.each { |scope, key, value| batch.add(INSERT, scope:, key:, value:) } }
      end

      private

      def rows
        data = File.file?(@path) ? YAML.safe_load_file(@path, aliases: true) : nil
        return [] unless data.is_a?(Hash)

        scopes(data).flat_map { |scope, settings| flat(settings).map { |name, value| [scope, name, JSON.generate(value)] } }
      rescue Psych::Exception
        []
      end

      def scopes(data)
        harnesses = data["harnesses"].is_a?(Hash) ? data["harnesses"] : {}
        [["global", data["global"]], *harnesses.to_a].select { |_scope, settings| settings.is_a?(Hash) }
      end

      def flat(hash, prefix = nil)
        hash.each_with_object({}) do |(key, value), entries|
          name = [prefix, key].compact.join(".")
          value.is_a?(Hash) ? entries.merge!(flat(value, name)) : entries[name] = value
        end
      end
    end
  end
end
