# frozen_string_literal: true

require "digest"
require "yaml"
require_relative "rows"
require_relative "../clock"
require_relative "../cli/command/refusal"
require_relative "../graph"

module Plastic
  class Config
    # Writes the settings rows of the machine database and prints config.yml
    # from them. The rows are the truth; the file holds no anchors. A file
    # changed by hand after the print is refused, never overwritten.
    class Store
      FILE = "config.yml"
      VERSION = 3

      UPSERT = 'INSERT OR REPLACE INTO "settings"("scope", "key", "value") VALUES (:scope, :key, :value)'
      IMPORT = 'INSERT OR IGNORE INTO "settings"("scope", "key", "value") VALUES (:scope, :key, :value)'
      RECORD = 'INSERT OR REPLACE INTO "printed_files"("path", "sha256", "at") VALUES (:path, :sha256, :at)'

      def initialize(home)
        @home = home
        @path = File.join(home, FILE)
        @rows = Rows.new(home)
      end

      def set(scope, key, value)
        refuse_hand_edit
        local.transaction { |batch| batch.add(UPSERT, scope:, key:, value: JSON.generate(value)) }
        print
      end

      def print
        text = document
        File.write(@path, text)
        local.transaction { |batch| batch.add(RECORD, path: FILE, sha256: Digest::SHA256.hexdigest(text), at: Plastic.now) }
      end

      def print_once
        return if @rows.printed(FILE)

        import
        print
      end

      private

      def import
        rows = Graph::SchemaHome3.rows(@path)
        local.transaction { |batch| rows.each { |scope, key, value| batch.add(IMPORT, scope:, key:, value:) } }
      end

      def local = Graph::Database.open_local(@home).fetch(:local)

      def refuse_hand_edit
        recorded = @rows.printed(FILE)
        return if recorded.nil? || !File.file?(@path) || recorded == Digest::SHA256.file(@path).hexdigest

        raise CLI::Command::Refusal.new("#{@path} changed since it was printed from the settings; move it aside, then run plastic config set KEY VALUE to print it again",
          next_command: "plastic config set KEY VALUE", because: "the file was edited by hand")
      end

      def document
        harnesses = (@rows.scopes - ["global"]).sort.to_h { |name| [name, @rows.scope(name)] }
        global = @rows.scope("global")
        YAML.dump({ "version" => VERSION, "global" => global, "harnesses" => harnesses }.reject { |key, value| value.is_a?(Hash) && value.empty? && key != "version" })
      end
    end
  end
end
