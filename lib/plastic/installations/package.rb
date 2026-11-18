# frozen_string_literal: true

require_relative "hook_entries"
require_relative "choices"
require_relative "hook_launcher"

module Plastic
  module Installations
    # The package an install copies from, the Plastic home it installs for and
    # the version it carries.
    Package = Data.define(:root, :home, :version, :settings, :clock) do
      def initialize(root:, home:, version:, settings:, clock: Time) = super

      def launcher = HookLauncher.new(root, home)

      def choices = Choices.new(settings)

      # The kernel's own hook groups, one for each event the harness registry
      # names. They are written before the registry's groups, because the
      # entries treat the old check-update launcher as stale.
      def entries
        HookEntries.new(command: launcher.command, config: settings.config, launchers: {}, former: launcher.former)
      end
    end
  end
end
