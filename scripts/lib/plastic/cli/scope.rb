# frozen_string_literal: true

require "yaml"

module Plastic
  class CLI
    # Which store a command works on. A named project wins. With no name, the
    # project whose repository holds the working directory wins, longest path
    # first, so a repository nested inside another resolves to the inner one.
    # With neither, the global store answers.
    #
    # Every path comes from the injected environment and home directory, so a
    # test points at a temporary home and never at the real one. The rows of
    # a store are read through the graphs, never here; the scope knows only
    # the home, the projects file and the store directories.
    class Scope
      UnknownProject = Class.new(StandardError)
      BrokenProjects = Class.new(StandardError)

      GLOBAL = "global"

      def initialize(env:, home:, slug: nil, directory: Dir.pwd)
        @env = env
        @home = home
        @requested = slug
        @directory = canonical_path(File.expand_path(directory))
      end

      def plastic_home
        @plastic_home ||= @env["PLASTIC_HOME"] || File.join(@home, ".plastic")
      end

      def slug
        @slug ||= resolve_slug
      end

      def root = File.join(plastic_home, "stores", slug)

      def known_slugs
        dirs = Dir.glob(File.join(plastic_home, "stores", "*")).select { |path| File.directory?(path) }
        (dirs.map { |path| File.basename(path) } | [GLOBAL]).sort
      end

      # The projects file at the home, as slug => path. A file that does not
      # parse stops the call and names itself, so no command runs on a guess.
      def projects
        path = File.join(plastic_home, "projects.yml")
        return {} unless File.exist?(path)

        data = YAML.safe_load_file(path)
        raise BrokenProjects, "#{path} does not hold a map of projects" unless data.is_a?(Hash)

        data.to_h { |slug, info| [slug.to_s, info.is_a?(Hash) ? info["path"].to_s : ""] }
      rescue Psych::SyntaxError => e
        raise BrokenProjects, "#{path} does not parse: #{e.message}"
      end

      private

      def resolve_slug
        return requested_slug if @requested

        directory_project || GLOBAL
      end

      def requested_slug
        return @requested if known_slugs.include?(@requested)

        raise UnknownProject, "no project named #{@requested.inspect}; this machine has #{known_slugs.join(", ")}"
      end

      def directory_project
        projects.reject { |_slug, path| path.empty? }
          .select { |_slug, path| inside?(path) }
          .max_by { |_slug, path| path.length }
          &.first
      end

      def inside?(path)
        path = canonical_path(File.expand_path(path))
        @directory == path || @directory.start_with?("#{path}#{File::SEPARATOR}")
      end

      def canonical_path(path)
        return File.realpath(path) if File.exist?(path)

        File.join(canonical_path(File.dirname(path)), File.basename(path))
      end
    end
  end
end
