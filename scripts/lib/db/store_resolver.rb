# encoding: UTF-8
# frozen_string_literal: true

require "yaml"

module Plastic
  module DB
    # Resolves which store (global or a project) a working directory belongs
    # to, and the plastic.db path for that store. Mirrors the CWD-match /
    # global-on-cwd-miss behavior Plastic already uses for the intent store
    # (see scripts/lib/qmd_sync.rb's slug matching), preserved exactly (D-AC6):
    # a cwd nested under a registered project's path resolves to that
    # project's store; any other cwd falls back to the global store.
    #
    # store_home is the directory that holds INDEX.md:
    #   global:  <plastic_home>
    #   project: <plastic_home>/projects/<slug>
    module StoreResolver
      module_function

      def resolve(cwd:, plastic_home: File.join(Dir.home, ".plastic"))
        cwd = File.expand_path(cwd)
        plastic_home = File.expand_path(plastic_home)
        slug = slug_for_cwd(cwd, plastic_home: plastic_home)
        store_home = slug ? File.join(plastic_home, "projects", slug) : plastic_home
        { store_home: store_home, db_path: db_path_for_store(store_home), slug: slug }
      end

      # DB path for a caller that already holds a store directory.
      def db_path_for_store(store_dir)
        File.join(store_dir, "plastic.db")
      end

      def slug_for_cwd(cwd, plastic_home:)
        projects = load_projects(plastic_home)
        match = projects.find do |_slug, info|
          path = info.is_a?(Hash) ? info["path"] : nil
          next false unless path
          root = File.expand_path(path)
          cwd == root || cwd.start_with?(root + File::SEPARATOR)
        end
        match && match[0].to_s
      end

      def load_projects(plastic_home)
        path = File.join(plastic_home, "projects.yml")
        return {} unless File.exist?(path)
        data = begin
          YAML.safe_load(File.read(path)) || {}
        rescue StandardError
          {}
        end
        projects = data.is_a?(Hash) ? data["projects"] : nil
        projects.is_a?(Hash) ? projects : {}
      end
    end
  end
end
