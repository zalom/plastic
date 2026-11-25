# frozen_string_literal: true

module Plastic
  module StoreLayout
    GLOBAL = "global"

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
  end
end
