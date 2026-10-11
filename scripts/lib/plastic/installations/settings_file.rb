# frozen_string_literal: true

require "json"
require_relative "rewrite"
require_relative "settings_edit"

module Plastic
  module Installations
    # The settings file a record names, with the entries the record lists
    # taken out. `edited` is nil when the file has none of them.
    SettingsFile = Data.define(:record) do
      def path = record.settings

      def edited
        settings = parsed
        return unless settings.is_a?(Hash)

        changed = SettingsEdit.new(record).call(settings)
        changed unless changed == settings
      end

      def rewrite
        settings = edited
        Rewrite.json(path, settings) if settings
      end

      private

      def parsed
        JSON.parse(File.read(path)) if File.file?(path)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
