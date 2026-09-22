# frozen_string_literal: true

module Plastic
  module StoreLayout
    GLOBAL = "global"
    PARENTS = %w[stores projects].freeze

    module_function

    def moved?(home)
      File.directory?(File.join(home, "stores"))
    end

    def global_root(home)
      moved?(home) ? File.join(home, "stores", GLOBAL) : home
    end

    def global_store(home)
      File.join(global_root(home), "store")
    end

    def projects_root(home)
      File.join(home, moved?(home) ? "stores" : "projects")
    end

    def project_root(home, slug)
      File.join(projects_root(home), slug)
    end

    def root(home, slug)
      (slug == GLOBAL) ? global_root(home) : project_root(home, slug)
    end

    def project_slugs(home)
      parent = projects_root(home)
      return [] unless File.directory?(parent)

      Dir.children(parent).reject { |entry| entry.start_with?(".") || entry == GLOBAL }.sort
    end

    def locate(store)
      root = File.dirname(File.expand_path(store))
      parent = File.dirname(root)
      return [root, GLOBAL] unless PARENTS.include?(File.basename(parent))

      [File.dirname(parent), File.basename(root)]
    end

    def home_and_scope(store)
      home, slug = locate(store)
      [home, (slug == GLOBAL) ? GLOBAL : "project:#{slug}"]
    end
  end
end
