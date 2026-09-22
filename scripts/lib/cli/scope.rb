# frozen_string_literal: true

require_relative "../store_layout"
require_relative "../index_entry"
require_relative "../store_discovery"

# Plastic::CLI::Scope (intent 363) - which store a command works on. Six skills
# used to restate this rule in prose; it is stated here once.
#
# A named project wins. With no name, the project whose repository holds the
# working directory wins, longest path first, so a repository nested inside
# another resolves to the inner one. With neither, the global store answers.
#
# Every path comes from the injected environment and home directory, so a test
# points at a temporary store and never at the real ~/.plastic.
module Plastic
  class CLI
    class Scope
      UnknownProject = Class.new(StandardError)

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

      def stores
        @stores ||= StoreDiscovery.discover(plastic_home)[:stores]
      end

      def slug
        @slug ||= resolve_slug
      end

      def root
        @root ||= found&.fetch(:root) || plastic_home
      end

      def store
        File.join(root, "store")
      end

      def index_path
        File.join(root, "INDEX.md")
      end

      def roadmaps_dir
        File.join(root, "roadmaps")
      end

      def active_entries
        return [] unless File.exist?(index_path)

        section(File.read(index_path)).filter_map do |line|
          match = IndexEntry.match(line)
          match && [match[1], match[2]]
        end
      end

      def active_ids
        active_entries.map(&:first)
      end

      def intent_dir(id)
        Dir.glob(File.join(store, "#{id}--*")).min
      end

      def directory_project
        @directory_project = project_for_directory unless defined?(@directory_project)
        @directory_project
      end

      def known_slugs
        stores.map { |store| store[:slug] }.sort
      end

      private

      def found
        stores.find { |store| store[:slug] == slug }
      end

      def resolve_slug
        return requested_slug if @requested

        directory_project || GLOBAL
      end

      def requested_slug
        return @requested if known_slugs.include?(@requested)

        raise UnknownProject,
          "no project named #{@requested.inspect}; this machine has #{known_slugs.join(", ")}"
      end

      def project_for_directory
        (repositories + stores.map { |store| [store[:slug], store[:root]] })
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

      def repositories
        StoreProvisioning.load_projects(plastic_home).filter_map do |slug, info|
          path = info.is_a?(Hash) ? info["path"].to_s : ""
          [slug, path] unless path.empty?
        end
      end

      def section(text)
        body = text.match(/^##\s+Active\s*$(.*?)(?=^##\s|\z)/m)
        body ? body[1].lines.map(&:strip) : []
      end
    end
  end
end
