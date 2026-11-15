# frozen_string_literal: true

require "fileutils"
require_relative "files"
require_relative "report"

module Plastic
  module Installations
    # Removes the plugin and marketplace install an earlier version made for
    # Claude Code, so the plugin layout and the flat skills never both exist.
    # Returns what it removed and prints it.
    class LegacyPlugin
      FOLDERS = [%w[plugins marketplaces plastic], %w[plugins cache plastic], %w[skills plastic]].freeze

      def initialize(claude_dir)
        @claude_dir = claude_dir
      end

      def call
        removed = folders + settings + marketplaces
        report(removed)
        removed
      end

      private

      def folders
        FOLDERS.map { |parts| File.join(@claude_dir, *parts) }.select { |path| File.directory?(path) }.each { |path| FileUtils.rm_rf(path) }
      end

      def settings
        path = File.join(@claude_dir, "settings.json")
        data = Files.read_json(path)
        return [] unless data

        changed = [drop(data, "enabledPlugins", "plastic@plastic"), drop(data, "extraKnownMarketplaces", "plastic")].any?
        return [] unless changed

        Files.write_json(path, data)
        ["settings.json: plastic@plastic plugin registration"]
      end

      def drop(data, section, key)
        return false unless data.dig(section, key)

        data[section].delete(key)
        data.delete(section) if data[section].empty?
        true
      end

      def marketplaces
        path = File.join(@claude_dir, "plugins", "known_marketplaces.json")
        known = Files.read_json(path)
        return [] unless known.is_a?(Hash) && known.key?("plastic")

        known.delete("plastic")
        Files.write_json(path, known)
        ["known_marketplaces.json: plastic"]
      end

      def report(removed)
        return if removed.empty?

        puts "  Migrated legacy plugin install:"
        removed.each { |entry| puts "     - #{Report.tilde(entry)}" }
      end
    end
  end
end
