# encoding: UTF-8

require "json"

module SessionStartHook
  # Whether a previous session's update check left a notice to show.
  module UpdateNotice
    def self.read(plastic_home)
      cache = load_cache(plastic_home)
      return nil unless cache["updateAvailable"]

      "Plastic update available: #{cache["current"]} -> #{cache["latest"]} — run `plastic update`"
    end

    def self.load_cache(plastic_home)
      cache_file = "#{plastic_home}/.cache/update-check.json"
      return {} unless File.exist?(cache_file)

      JSON.parse(File.read(cache_file))
    rescue
      {}
    end
  end
end
