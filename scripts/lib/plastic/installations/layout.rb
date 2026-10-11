# frozen_string_literal: true

require_relative "../../hook_registry"

module Plastic
  module Installations
    # Where one installer keeps its settings and instruction files, and
    # which hook commands are Plastic's there.
    Layout = Data.define(:folder, :settings, :purge, :instructions, :markers) do
      def settings_path(config) = File.join(config.fetch(folder), settings)

      def instructions_path(config) = File.join(config.fetch(folder), instructions)

      def plastic?(command) = HookRegistry.public_send(purge, command)
    end
  end
end
