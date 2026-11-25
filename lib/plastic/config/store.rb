# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"
require_relative "import"
require_relative "rows"
require_relative "../clock"

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

      def initialize(home, database:, clock: Time)
        @home = home
        @database = database
        @clock = clock
        @rows = Rows.new(database)
      end

      def set(scope, key, value)
        refuse_hand_edit
        @rows.set(scope, key, value)
        print
      end

      def print
        text = document
        File.write(path, text)
        @rows.record_print(FILE, text, Plastic.timestamp(@clock.now))
      end

      # Prints config.yml so it matches the rows. The first print imports the file into rows first. A later call prints
      # again only when the file is still the recorded print and the rows changed under it, as after a home migration
      # that removes a retired setting; a file changed by hand is kept and named.
      def print_current
        return problem || reprint if @rows.printed(FILE)

        reason = unreadable
        return format(UNREADABLE, reason) if reason

        back_up
        Import.new(path, into: @database).call
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

      def reprint
        print unless File.file?(path) && File.read(path) == document
        nil
      end

      def path = File.join(@home, FILE)

      def edited_line
        recorded = @rows.printed(FILE)
        return if recorded.nil? || !File.file?(path) || recorded == Digest::SHA256.file(path).hexdigest

        format(LINE, path)
      end

      def unreadable
        return unless File.file?(path)

        data = YAML.safe_load_file(path, aliases: true)
        "it is not a mapping" unless data.nil? || data.is_a?(Hash)
      rescue Psych::Exception => error
        error.message.lines.first.strip
      end

      def back_up
        return unless File.file?(path)

        FileUtils.mkdir_p(File.join(@home, "backups"))
        FileUtils.cp(path, File.join(@home, "backups", "config-#{@clock.now.utc.strftime("%Y%m%d%H%M%S")}.yml"))
      end

      def refuse_hand_edit
        line = edited_line
        raise HandEdited.new(line, path) if line
      end

      def document
        harnesses = (@rows.scopes - ["global"]).sort.to_h { |name| [name, @rows.scope(name)] }
        global = @rows.scope("global")
        YAML.dump({ "version" => VERSION, "global" => global, "harnesses" => harnesses }.reject { |key, value| value.is_a?(Hash) && value.empty? && key != "version" })
      end
    end
  end
end
