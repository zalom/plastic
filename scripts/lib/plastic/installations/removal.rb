# frozen_string_literal: true

require_relative "roots"
require_relative "section"
require_relative "settings_file"

module Plastic
  module Installations
    # Takes out exactly what one record lists, then the record. Files and
    # folders go only inside the record's roots, and a folder only when it is
    # empty. Returns each path it removed or changed; `planned` names them
    # first and changes nothing.
    class Removal
      def initialize(record, plastic_home:)
        @record = record
        @plastic_home = plastic_home
        @roots = Roots.new(record.roots)
        @settings = SettingsFile.new(record)
      end

      def call
        changed = removed_files + removed_folders + [@settings.rewrite, *stripped_sections].compact
        Installations.delete(@plastic_home, @record.harness)
        changed
      end

      def planned = removals.map { |path| ["remove:", path] } + changes.map { |path| ["change:", path] }

      private

      def removals
        [*@record.files.select { |file| removable?(file) }, *@record.folders.select { |folder| existing_folder?(folder) },
          Installations.path(@plastic_home, @record.harness)]
      end

      def changes = [*(@settings.path if @settings.edited), *sections.map(&:file).select { |file| File.file?(file) }]

      def existing_folder?(folder) = @roots.inside?(folder) && File.directory?(folder)

      def removed_files = @record.files.select { |file| removable?(file) }.each { |file| File.delete(file) }

      def removable?(file) = @roots.inside?(file) && File.file?(file)

      def removed_folders = @record.folders.sort_by { |folder| -folder.length }.select { |folder| removed_folder?(folder) }

      def removed_folder?(folder) = existing_folder?(folder) && Dir.empty?(folder) && Dir.rmdir(folder).zero?

      def sections = @record.sections.map { |section| Section.from_h(section) }

      def stripped_sections = sections.filter_map(&:strip)
    end
  end
end
