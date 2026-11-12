# frozen_string_literal: true

require "fileutils"

module Plastic
  class CLI
    # The projects.yml file at the home. A new project is added as text, so
    # every other entry, key and comment stays as written.
    class ProjectsFile
      HEADER = /^projects:[ \t]*(?:\{\})?[ \t]*(?:#.*)?\n?/

      # Both paths name the same folder on disk.
      def self.same_folder?(known, path) = File.directory?(known) && File.realpath(known) == File.realpath(path)

      def initialize(path)
        @path = path
      end

      def add(slug, folder)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(scratch, with_entry("  #{slug}:\n    path: #{folder}\n"))
        File.rename(scratch, @path)
      end

      private

      def scratch = "#{@path}.new"

      def text = File.exist?(@path) ? File.read(@path) : ""

      def with_entry(entry)
        return text.sub(HEADER) { |line| "#{line.sub("{}", "").rstrip}\n#{entry}" } if text.match?(/^projects:/)

        "#{text}#{"\n" unless text.empty? || text.end_with?("\n")}projects:\n#{entry}"
      end
    end
  end
end
