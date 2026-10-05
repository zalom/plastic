# frozen_string_literal: true

require_relative "../../installer_release"
require_relative "installation_hooks"
require_relative "installation_launcher"
require_relative "installation_lock"

module Plastic
  module Workflows
    # Reads the parts of an installation that a working `plastic` needs and
    # names a repair for each broken one. It reads files and changes none.
    class InstallationHealth
      Check = Data.define(:label, :value, :repair)
      UNMANAGED = "no release is installed; this plastic runs outside a release"
      INCOMPLETE = "switch to a complete release with plastic rollback or plastic update"

      def self.of(context, ruby_version: RUBY_VERSION)
        scope = context.scope
        home = scope.home
        new(share: scope.setting("PLASTIC_SHARE", File.join(home, ".local", "share", "plastic")),
          bin: scope.setting("PLASTIC_BIN", File.join(home, ".local", "bin")), path: scope.setting("PATH", ""), home:, ruby_version:)
      end

      def initialize(share:, bin:, path:, home:, ruby_version:)
        @share = share
        @launcher = InstallationLauncher.new(bin:, path:)
        @home = home
        @ruby_version = ruby_version
      end

      def checks
        managed? ? release_checks(active, activation.previous_version || "none") : unmanaged_checks
      end

      def managed? = File.file?(File.join(activation.active_path, "VERSION"))

      private

      attr_reader :share, :launcher, :home, :ruby_version

      def activation = (@activation ||= InstallerRelease::Activation.new(home: share))

      def active = activation.active_version

      def unmanaged_checks = [Check.new("active:", "none; no release is activated", nil), Check.new("installation:", UNMANAGED, nil), ruby]

      def release_checks(active, previous)
        [Check.new("active:", active, nil), Check.new("previous:", previous, nil), launcher.check, ruby, bundle, hooks, InstallationLock.new(share).check]
      end

      def hooks = InstallationHooks.new(home:, active: active_launcher).check

      def active_launcher = File.join(share, "active", "bin", "plastic")

      def ruby = Check.new("ruby:", ruby_version, (ruby_version.to_i >= 4) ? nil : "install Ruby 4.0 or later")

      def bundle
        setup = File.join(share, "active", "runtime", "bundle", "bundler", "setup.rb")
        File.file?(setup) ? Check.new("sqlite3 bundle:", "present", nil) : Check.new("sqlite3 bundle:", "missing (#{setup})", INCOMPLETE)
      end
    end
  end
end
