# frozen_string_literal: true

module Plastic
  module Installations
    # The home keeps its databases out of version control: `apply` adds the
    # `*.db` and `*.db-*` lines (the databases and their journal, wal and shm files) to the home's .gitignore when they are missing, once.
    class HomeIgnore
      LINES = ["*.db", "*.db-*"].freeze

      def initialize(home)
        @file = File.join(home, ".gitignore")
      end

      def apply = "#{LINES.join(" ")} #{add ? "added" : "listed"}"

      private

      def add
        missing = LINES - lines
        return false if missing.empty?

        File.write(@file, "#{kept_text}#{missing.join("\n")}\n")
        true
      end

      def lines = File.file?(@file) ? File.readlines(@file, chomp: true) : []

      def kept_text = File.exist?(@file) ? File.read(@file).sub(/(?<=[^\n])\z/, "\n") : ""
    end
  end
end
