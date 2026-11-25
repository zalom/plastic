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

      def self.drop(data, section, key)
        return false unless data.dig(section, key)

        entries = data[section]
        entries.delete(key)
        data.delete(section) if entries.empty?
        true
      end

      def self.drop_key(hash, key)
        return false unless hash.is_a?(Hash) && hash.key?(key)

        hash.delete(key)
        true
      end

      private

      def folders
        FOLDERS.map { |parts| File.join(@claude_dir, *parts) }.select { |path| File.directory?(path) }.each { |path| FileUtils.rm_rf(path) }
      end

      def settings
        path = File.join(@claude_dir, "settings.json")
        changed = Files.edit_json(path) { |data| [LegacyPlugin.drop(data, "enabledPlugins", "plastic@plastic"), LegacyPlugin.drop(data, "extraKnownMarketplaces", "plastic")].any? }
        changed ? ["settings.json: plastic@plastic plugin registration"] : []
      end

      def marketplaces
        path = File.join(@claude_dir, "plugins", "known_marketplaces.json")
        changed = Files.edit_json(path) { |known| LegacyPlugin.drop_key(known, "plastic") }
        changed ? ["known_marketplaces.json: plastic"] : []
      end

      def report(removed)
        return if removed.empty?

        puts "  Migrated legacy plugin install:"
        removed.each { |entry| puts "     - #{Report.tilde(entry)}" }
      end
    end
  end
end
