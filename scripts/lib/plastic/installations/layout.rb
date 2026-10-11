# frozen_string_literal: true

require_relative "../../hook_registry"

module Plastic
  module Installations
    # Where one installer keeps its settings and instruction files, and
    # which hook commands are Plastic's there. An installer with neither has
    # no path for them.
    Layout = Data.define(:folder, :settings, :purge, :instructions, :markers) do
      def settings_path(config) = settings && File.join(config.fetch(folder), settings)

      def instructions_path(config) = instructions && File.join(config.fetch(folder), instructions)

      def plastic?(command) = HookRegistry.public_send(purge, command)
    end
  end
end
