# frozen_string_literal: true

module Plastic
  class CLI
    # The help chapters that name no command, one Markdown file each.
    class Topics
      def initialize(directory, table)
        @directory = directory
        @table = table
      end

      # The chapter the words name, or nothing when they name a command or no file.
      def read(words)
        return unless words.one? && !CLI.find(words, @table)

        path = File.join(@directory, "#{words.first}.md")
        File.read(path) if File.file?(path)
      end
    end
  end
end
