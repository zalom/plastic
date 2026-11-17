# frozen_string_literal: true

require_relative "check"

module Plastic
  module Doctor
    # The home keeps its databases out of version control: this adds the
    # `*.db` and `*.db-*` lines (the databases and their journal, wal and shm files) to the home's .gitignore when they are missing, once.
    class HomeIgnore
      LINES = ["*.db", "*.db-*"].freeze

      def initialize(home)
        @file = File.join(home, ".gitignore")
      end

      def check
        added = add
        Check.ok(".gitignore:", "#{LINES.join(" ")} #{added ? "added" : "listed"}")
      end

      private

      def add
        missing = LINES - lines
        return false if missing.empty?

        File.write(@file, "#{ensure_newline if File.exist?(@file)}#{missing.join("\n")}\n")
        true
      end

      def lines = File.file?(@file) ? File.readlines(@file, chomp: true) : []

      def ensure_newline
        text = File.read(@file)
        (text.empty? || text.end_with?("\n")) ? text : "#{text}\n"
      end
    end
  end
end
