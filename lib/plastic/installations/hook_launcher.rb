# frozen_string_literal: true

module Plastic
  module Installations
    # The launcher a hook runs. A package installed as a release runs from
    # share/releases/VERSION, and its hooks run the active launcher, so the
    # next activation needs no hook rewrite. Any other package runs the
    # launcher copied into the Plastic home.
    class HookLauncher
      def initialize(package_root, home)
        @package_root = package_root
        @home = home
      end

      def command
        releases = File.dirname(@package_root)
        return File.join(@home, "exe", "plastic") unless File.basename(releases) == "releases"

        File.join(File.dirname(releases), "active", "bin", "plastic")
      end

      # The launchers earlier installs wrote, which the hooks entries replace.
      def former = [File.join(@home, "bin", "plastic"), File.join(@home, "exe", "plastic")] - [command]
    end
  end
end
