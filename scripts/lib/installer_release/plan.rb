# frozen_string_literal: true

require "json"

module InstallerRelease
  # Reads release state and describes the next installer operation. Planning
  # has no file effects: a command can show a preview against a missing home
  # without creating a release directory, a store, or a routine receipt.
  class Plan
    def initialize(home:, package_root: ENV.fetch("PLASTIC_PACKAGE_ROOT", Dir.pwd))
      @home = home
      @package_root = package_root
    end

    def installed_version
      active_version || package_version
    end

    def channel
      return "alpha" if installed_version.include?("-alpha")
      return "beta" if installed_version.include?("-beta")

      "stable"
    end

    def preview(verb)
      { verb: verb, version: installed_version, channel: channel,
        message: "a verified release manifest is required before Plastic can write files" }
    end

    private

    attr_reader :home, :package_root

    def active_version
      path = File.join(home, "active", "VERSION")
      File.file?(path) ? File.read(path).strip : nil
    end

    def package_version
      JSON.parse(File.read(File.join(package_root, "package.json"))).fetch("version")
    end
  end
end
