# frozen_string_literal: true

require "fileutils"
require_relative "../cli/command"
require_relative "../graph"

module Plastic
  module Commands
    # Registers a project in projects.yml and leaves its store ready, so an
    # intent can be opened at once. The other lines of the file stay as they
    # are. The same name at the same path again changes nothing.
    class ProjectNew < CLI::Command
      NAME = /\A[a-z0-9][a-z0-9-]*\z/
      HEADER = /^projects:[ \t]*(?:\{\})?[ \t]*(?:#.*)?\n?/

      argument :slug, label: "SLUG", text: "the project's name: lowercase letters, digits and dashes"
      argument :path, label: "PATH", text: "the project's repository folder"
      writes :work, :knowledge, :references

      def call
        slug = checked_slug
        path = checked_path
        register(slug, path) unless same?(scope.projects[slug], path)
        make_ready(slug)
        output.row("project", "#{slug}: #{path}")
        output.next_step("plastic intent new TITLE --project #{slug}", because: "the project is registered and its store is ready")
      end

      private

      def checked_slug
        slug = parsed[:slug]
        raise CLI::Command::Usage, "the name must be lowercase letters, digits and dashes" unless NAME.match?(slug)
        raise CLI::Command::Refusal, "#{CLI::Scope::GLOBAL} is the name of the global store, not of a project" if slug == CLI::Scope::GLOBAL

        slug
      end

      def checked_path
        path = File.expand_path(parsed[:path], environment.directory)
        raise CLI::Command::Failure, "#{path} is not a directory" unless File.directory?(path)

        path
      end

      def same?(known, path) = known && File.directory?(known) && File.realpath(known) == File.realpath(path)

      def register(slug, path)
        known = scope.projects[slug]
        raise CLI::Command::Refusal, "#{slug} is registered at #{known}, not at #{path}; edit projects.yml to move it" if known

        write(entry_text(current_text, slug, path))
      end

      def projects_file = File.join(scope.plastic_home, "projects.yml")

      def current_text = File.exist?(projects_file) ? File.read(projects_file) : ""

      def entry_text(text, slug, path)
        entry = "  #{slug}:\n    path: #{path}\n"
        return text.sub(HEADER) { |line| "#{line.sub("{}", "").rstrip}\n#{entry}" } if text.match?(/^projects:/)

        "#{text}#{"\n" unless text.empty? || text.end_with?("\n")}projects:\n#{entry}"
      end

      def write(text)
        FileUtils.mkdir_p(scope.plastic_home)
        scratch = "#{projects_file}.new"
        File.write(scratch, text)
        File.rename(scratch, projects_file)
      end

      def make_ready(slug)
        graphs = Graph.open(home: scope.plastic_home, store: slug, session: environment.session)
        graphs.databases.values_at(:knowledge, :work, :references).each { |database| database.rows("SELECT 1") }
      end
    end
  end
end
