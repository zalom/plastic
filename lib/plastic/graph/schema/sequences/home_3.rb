# frozen_string_literal: true

require "yaml"

module Plastic
  module Graph
    # Home migration 3, frozen. The machine database holds the settings as
    # rows and the hash of each file printed from them, and the settings of a
    # sectioned config.yml move into the rows once, with anchors and merge keys
    # resolved to plain values. Its statements are written out and never call
    # the live schema. The runner holds the write lock around it.
    module SchemaHome3
      TABLES = { "local" => %w[command_runs sessions locks settings printed_files] }.freeze

      TEXT = {
        local: <<~SQL
          CREATE TABLE IF NOT EXISTS "settings"("scope" TEXT NOT NULL, "key" TEXT NOT NULL, "value" TEXT NOT NULL, UNIQUE("scope", "key"));
          CREATE TABLE IF NOT EXISTS "printed_files"("path" TEXT NOT NULL, "sha256" TEXT NOT NULL, "at" TEXT, UNIQUE("path"));
        SQL
      }.freeze

      INSERT = 'INSERT OR IGNORE INTO "settings"("scope", "key", "value") VALUES (?, ?, ?)'

      module_function

      def texts = TEXT.values + [INSERT]

      def apply(connection, key)
        connection.execute_batch(TEXT.fetch(key))
        rows(File.join(File.dirname(connection.filename), "config.yml")).each { |row| connection.execute(INSERT, row) }
      end

      # The [scope, dotted key, JSON value] rows of the sections of a config file; none when it is missing or does not parse.
      def rows(path)
        data = File.file?(path) ? YAML.safe_load_file(path, aliases: true) : nil
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
