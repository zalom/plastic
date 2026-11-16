# frozen_string_literal: true

require_relative "check"

module Plastic
  module Doctor
    # The home keeps its databases out of version control: this adds the
    # `*.db` line to the home's .gitignore when it is missing, once.
    class HomeIgnore
      LINE = "*.db"

      def initialize(home)
        @file = File.join(home, ".gitignore")
      end

      def check
        added = add
        Check.ok(".gitignore:", added ? "#{LINE} added" : "#{LINE} listed")
      end

      private

      def add
        return false if lines.include?(LINE)

        File.write(@file, "#{File.exist?(@file) ? ensure_newline : ""}#{LINE}\n")
        true
      end

      def lines = File.file?(@file) ? File.readlines(@file, chomp: true) : []

      def ensure_newline
        text = File.read(@file)
        text.empty? || text.end_with?("\n") ? text : "#{text}\n"
      end
    end
  end
end
