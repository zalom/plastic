# encoding: UTF-8

require "json"
require_relative "../boot_banner"
require_relative "../doctor_core"

module SessionStartHook
  # The one thing every boot always gets, independent of anything below it
  # that can raise (intent 36a reuses Doctor's own --core checks in-process).
  module CoreBanner
    def self.render(plastic_home:, plugin_root:)
      version = current_version(plastic_home, plugin_root)
      health = core_health(plastic_home)
      [BootBanner.render(health: health, version: version), version]
    end

    def self.core_health(plastic_home)
      Doctor.new(plastic_home: plastic_home).run_core_checks("claude")
    rescue
      nil
    end

    def self.current_version(plastic_home, plugin_root)
      version_file = "#{plastic_home}/VERSION"
      return File.read(version_file).strip if File.exist?(version_file)
      return nil unless plugin_root && !plugin_root.empty?

      plugin_json_version(plugin_root)
    end

    def self.plugin_json_version(plugin_root)
      plugin_json_path = "#{plugin_root}/.claude-plugin/plugin.json"
      return nil unless File.exist?(plugin_json_path)

      parsed = safe_json(plugin_json_path)
      parsed["version"]
    end

    def self.safe_json(path)
      JSON.parse(File.read(path))
    rescue
      {}
    end
  end
end
