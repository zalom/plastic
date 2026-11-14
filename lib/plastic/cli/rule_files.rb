# frozen_string_literal: true

require_relative "command"

module Plastic
  class CLI
    # The two rule files of a project folder. A file that is there stays byte for byte; an
    # absent one is written.
    class RuleFiles
      AGENTS = "AGENTS.md"
      CLAUDE = "CLAUDE.md"

      def initialize(folder, name)
        @folder = folder
        @name = name
      end

      # Writes the absent files and returns the names it wrote.
      def write_absent
        contents.filter_map do |file, text|
          path = File.join(@folder, file)
          next if File.exist?(path)

          File.write(path, text)
          file
        end
      end

      private

      def contents
        { AGENTS => "# #{@name}\n\nRules for agents working on this repository.\n", CLAUDE => "@#{AGENTS}\n" }
      end
    end
  end
end
