# frozen_string_literal: true

require_relative "removal_folders"
require_relative "roots"
require_relative "section"
require_relative "settings_file"

module Plastic
  module Installations
    # Takes out exactly what one record lists, then the record. Files and
    # folders go only inside the record's roots, and a folder only when it is
    # empty, and so is a folder the removal emptied. Returns a row for each
    # path: `removed:` for a path that is gone, `stripped:` for a settings or
    # instruction file that stays with the Plastic part taken out. `planned`
    # names them first and changes nothing.
    class Removal
      def initialize(record, plastic_home:)
        @record = record
        @plastic_home = plastic_home
        @roots = Roots.new(record.roots)
        @settings = SettingsFile.new(record)
      end

      def call
        files = removed_files
        rows = (files + folders.removed(files)).map { |path| ["removed:", path] } + rewritten
        Installations.delete(@plastic_home, @record.harness)
        rows
      end

      def planned = removals.map { |path| ["remove:", path] } + changes.map { |path| ["change:", path] }

      private

      def removals
        files = @record.files.select { |file| removable?(file) }
        [*files, *folders.planned(files), Installations.path(@plastic_home, @record.harness)]
      end

      def changes = [*(@settings.path if @settings.edited), *sections.map(&:file).select { |file| File.file?(file) }]

      def removed_files = @record.files.select { |file| removable?(file) }.each { |file| File.delete(file) }

      def folders = RemovalFolders.new(@record, @roots)

      def removable?(file) = @roots.inside?(file) && File.file?(file)

      def rewritten
        [@settings.rewrite, *stripped_sections].compact.map { |path| [File.exist?(path) ? "stripped:" : "removed:", path] }
      end

      def sections = @record.sections.map { |section| Section.from_h(section) }

      def stripped_sections = sections.filter_map(&:strip)
    end
  end
end
