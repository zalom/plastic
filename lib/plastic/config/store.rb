# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"
require_relative "rows"
require_relative "../clock"
require_relative "../graph/database"
require_relative "../graph/origin"
require_relative "../graph/schema/sequences/home_3"

module Plastic
  class Config
    # Writes the settings rows of the machine database and prints config.yml
    # from them. The rows are the truth; the file holds no anchors. A file
    # changed by hand after the print is refused, never overwritten.
    # config.yml changed after it was printed from the settings.
    class HandEdited < StandardError
      attr_reader :path

      def initialize(message, path)
        super(message)
        @path = path
      end
    end

    class Store
      LINE = "%s changed since it was printed from the settings; move it aside, then run plastic config set KEY VALUE to print it again"
      UNREADABLE = "config.yml could not be read (%s); fix it and run plastic update"
      REPAIR = "plastic config set KEY VALUE"

      FILE = "config.yml"
      VERSION = 3

      UPSERT = 'INSERT OR REPLACE INTO "settings"("scope", "key", "value") VALUES (:scope, :key, :value)'
      IMPORT = 'INSERT OR IGNORE INTO "settings"("scope", "key", "value") VALUES (:scope, :key, :value)'
      RECORD = 'INSERT OR REPLACE INTO "printed"("path", "sha256", "at", "origin_id") VALUES (:path, :sha256, :at, :origin_id)'

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

      # Copies the settings rows of another home into this one, and prints nothing.
      def copy_rows_from(other)
        rows = Rows.new(other).all
        local.transaction { |batch| rows.each { |scope, key, value| batch.add(UPSERT, scope:, key:, value:) } }
      end

      def print
        text = document
        File.write(@path, text)
        local.transaction { |batch| batch.add(RECORD, path: FILE, sha256: Digest::SHA256.hexdigest(text), at: Plastic.now, origin_id: Graph::Origin.new(@home).id) }
      end

      def print_once
        return problem if @rows.printed(FILE)

        reason = unreadable
        return format(UNREADABLE, reason) if reason

        back_up
        import
        print
        nil
      end

      # The line that says why config.yml is not the print of the rows, or nil.
      def problem
        return edited_line if @rows.printed(FILE)

        reason = unreadable
        reason && format(UNREADABLE, reason)
      end

      private

      def edited_line
        recorded = @rows.printed(FILE)
        return if recorded.nil? || !File.file?(@path) || recorded == Digest::SHA256.file(@path).hexdigest

        format(LINE, @path)
      end

      def unreadable
        return unless File.file?(@path)

        data = YAML.safe_load_file(@path, aliases: true)
        "it is not a mapping" unless data.nil? || data.is_a?(Hash)
      rescue Psych::Exception => error
        error.message.lines.first.strip
      end

      def back_up
        return unless File.file?(@path)

        FileUtils.mkdir_p(File.join(@home, "backups"))
        FileUtils.cp(@path, File.join(@home, "backups", "config-#{Time.now.utc.strftime("%Y%m%d%H%M%S")}.yml"))
      end

      def import
        rows = Graph::SchemaHome3.rows(@path)
        local.transaction { |batch| rows.each { |scope, key, value| batch.add(IMPORT, scope:, key:, value:) } }
      end

      def local = Graph::Database.open_local(@home).fetch(:local)

      def refuse_hand_edit
        line = edited_line
        raise HandEdited.new(line, @path) if line
      end

      def document
        harnesses = (@rows.scopes - ["global"]).sort.to_h { |name| [name, @rows.scope(name)] }
        global = @rows.scope("global")
        YAML.dump({ "version" => VERSION, "global" => global, "harnesses" => harnesses }.reject { |key, value| value.is_a?(Hash) && value.empty? && key != "version" })
      end
    end
  end
end
