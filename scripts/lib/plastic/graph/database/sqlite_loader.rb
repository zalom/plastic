# frozen_string_literal: true

require "rbconfig"

module Plastic
  module Graph
    class Database
      # Loads the locked sqlite3 gem without starting RubyGems when its standard
      # installation root is present. RubyGems remains the portable fallback.
      module SqliteLoader
        VERSION = "2.9.6"

        def self.load!(roots: gem_roots)
          return validate! if defined?(SQLite3)

          fast_load(roots) || fallback_load
          validate!
        end

        def self.gem_roots
          [*environment_roots, ruby_gem_root, bundle_gem_root].compact.uniq
        end

        def self.fast_load(roots)
          path = sqlite_load_path(roots)
          return false unless path

          $LOAD_PATH.unshift(path)
          require "sqlite3"
          true
        rescue LoadError
          $LOAD_PATH.delete(path)
          false
        end

        def self.fallback_load
          require "rubygems"
          require "sqlite3"
        end

        def self.validate!
          return if SQLite3::VERSION == VERSION

          raise LoadError, "Plastic requires sqlite3 #{VERSION} (found #{SQLite3::VERSION})"
        end

        def self.environment_roots
          %w[GEM_HOME GEM_PATH BUNDLE_PATH].flat_map { |key| ENV.fetch(key, "").split(File::PATH_SEPARATOR) }.reject(&:empty?)
        end

        def self.ruby_gem_root
          File.join(RbConfig::CONFIG.fetch("rubylibprefix"), "gems", RbConfig::CONFIG.fetch("ruby_version"))
        end

        def self.bundle_gem_root
          File.join(Dir.pwd, "vendor", "bundle", "ruby", RbConfig::CONFIG.fetch("ruby_version"))
        end

        def self.sqlite_load_path(roots)
          roots.flat_map { |root| Dir.glob(File.join(root, "gems", "sqlite3-*", "lib")) }.find { |path| compatible?(path) }
        end

        def self.compatible?(path)
          match = /sqlite3-#{Regexp.escape(VERSION)}(?:-([a-z0-9_-]+))?\z/.match(File.basename(File.dirname(path)))
          match && compatible_platform?(match[1])
        end

        def self.compatible_platform?(platform)
          platform.nil? || platform == "ruby" || RbConfig::CONFIG.fetch("arch").start_with?(platform)
        end
      end
    end
  end
end
