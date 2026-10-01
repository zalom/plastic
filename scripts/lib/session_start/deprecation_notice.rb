# encoding: UTF-8

require "yaml"
require_relative "../read_config"
require_relative "../version_number"

module SessionStartHook
  # Which deprecations are still live: a notice whose removal version is
  # already behind the installed one has nothing left to warn about. Only a
  # critical notice outlives its own removal.
  module DeprecationNotice
    # What a deprecation is checked against: the installed version, the
    # current release string, and the ids the owner already dismissed.
    Check = Struct.new(:installed, :current_version, :dismissed)

    def self.active(plastic_home:, plugin_root:, current_version:)
      deprecations = load(plastic_home, plugin_root)
      check = Check.new(installed: VersionNumber.parse(current_version), current_version: current_version,
        dismissed: read_dismissed)
      deprecations.select { |dep| live?(dep, check) }
    end

    def self.load(plastic_home, plugin_root)
      dep_file = deprecations_path(plastic_home, plugin_root)
      return [] unless File.exist?(dep_file)

      safe_load_yaml(dep_file)["deprecations"] || []
    end

    def self.deprecations_path(plastic_home, plugin_root)
      (plugin_root && !plugin_root.empty?) ? "#{plugin_root}/deprecations.yml" : "#{plastic_home}/deprecations.yml"
    end

    def self.safe_load_yaml(path)
      YAML.safe_load_file(path)
    rescue
      {}
    end

    def self.read_dismissed
      Array(ReadConfig.resolve("deprecations_dismissed"))
    rescue
      []
    end

    def self.live?(dep, check)
      return true if dep["severity"] == "critical"
      return false if removed_before_install?(dep, check)
      return true if removed_at_current?(dep, check)

      !check.dismissed.include?(dep["id"])
    end

    def self.removed_before_install?(dep, check)
      installed = check.installed
      removal = VersionNumber.parse(dep["removal"])
      installed && removal && removal < installed
    end

    def self.removed_at_current?(dep, check)
      current = check.current_version
      current && dep["removal"] == current
    end

    def self.lines(deprecations)
      return [] unless deprecations.any?

      [""] + deprecations.flat_map { |dep| lines_for(dep) }
    end

    def self.lines_for(dep)
      severity = dep["severity"] || "info"
      (severity == "info") ? info_line(dep) : warning_lines(dep)
    end

    def self.info_line(dep)
      link = dep["link"]
      line = "i Deprecation: #{dep["summary"] || dep["id"]}. Removed in: #{dep["removal"]}."
      [link ? "#{line} See: #{link}" : line]
    end

    def self.warning_lines(dep)
      [warning_marker(dep), *migration_lines(dep), removal_trail(dep)]
    end

    def self.warning_marker(dep)
      marker = (dep["severity"] == "critical") ? "!! DEPRECATION (critical)" : "! DEPRECATION (warning)"
      "#{marker}: #{dep["summary"] || dep["id"]}"
    end

    def self.migration_lines(dep)
      steps = dep["migration_steps"] || []
      return [] if steps.empty?

      ["  Migration steps:"] + steps.each_with_index.map { |step, position| "  #{position + 1}. #{step}" }
    end

    def self.removal_trail(dep)
      link = dep["link"]
      trail = "  Removed in: #{dep["removal"]}"
      link ? "#{trail} | Details: #{link}" : trail
    end
  end
end
