# frozen_string_literal: true

require "json"
require_relative "rewrite"
require_relative "roots"
require_relative "section"
require_relative "settings_edit"

module Plastic
  module Installations
    # Takes out exactly what one record lists, then the record. Files and
    # folders go only inside the record's roots, and a folder only when it is
    # empty. Returns each path it removed or changed.
    class Removal
      def initialize(record, plastic_home:)
        @record = record
        @plastic_home = plastic_home
        @roots = Roots.new(record.roots)
      end

      def call
        changed = removed_files + removed_folders + [edited_settings, *stripped_sections].compact
        Installations.delete(@plastic_home, @record.harness)
        changed
      end

      private

      def removed_files = @record.files.select { |file| removable?(file) }.each { |file| File.delete(file) }

      def removable?(file) = @roots.inside?(file) && File.file?(file)

      def removed_folders = @record.folders.sort_by { |folder| -folder.length }.select { |folder| removed_folder?(folder) }

      def removed_folder?(folder) = @roots.inside?(folder) && File.directory?(folder) && Dir.empty?(folder) && Dir.rmdir(folder).zero?

      def edited_settings
        settings = parsed_settings
        return unless settings.is_a?(Hash)

        edited = SettingsEdit.new(@record).call(settings)
        Rewrite.json(settings_path, edited) unless edited == settings
      end

      def settings_path = @record.settings

      def parsed_settings
        JSON.parse(File.read(settings_path)) if File.file?(settings_path)
      rescue JSON::ParserError
        nil
      end

      def stripped_sections = @record.sections.filter_map { |section| Section.from_h(section).strip }
    end
  end
end
