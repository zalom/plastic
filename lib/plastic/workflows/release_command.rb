# frozen_string_literal: true

require "rbconfig"
require "shellwords"

module Plastic
  module Workflows
    # The command line that installs a downloaded release or switches to an
    # installed one. The active release's own install-release script runs it,
    # under the Ruby that runs Plastic. Plastic prints the line and starts
    # nothing.
    ReleaseCommand = Data.define(:ruby, :share, :bin, :plastic_home, :user_home) do
      def self.of(scope)
        home = scope.home
        share = scope.setting("PLASTIC_SHARE", File.join(home, ".local", "share", "plastic"))
        bin = scope.setting("PLASTIC_BIN", File.join(home, ".local", "bin"))
        new(RbConfig.ruby, share, bin, scope.plastic_home, home)
      end

      def install(active, version) = line(active, "--directory", File.join(share, "download"), "--version", version)

      def switch(active, version) = line(active, "--switch", version)

      private

      def line(active, *choice)
        script = File.join(share, "releases", active, "scripts", "install-release")
        [ruby, "--disable-gems", "-rrbconfig", script, *choice,
          "--home", share, "--bin", bin, "--plastic-home", plastic_home, "--user-home", user_home].map { |word| Shellwords.escape(word) }.join(" ")
      end
    end
  end
end
