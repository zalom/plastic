# frozen_string_literal: true

require_relative "roots"

module Plastic
  module Installations
    # The folders a removal may take: the ones a record lists, the parents of the
    # files it removes, and the install folders, each inside the record's roots and
    # only when empty. `planned` names them before the removal, counting the files
    # it will delete; `removed` takes them after.
    class RemovalFolders
      def initialize(record, roots)
        @record = record
        @roots = roots
      end

      def planned(files)
        gone = files.to_set
        candidates(files).select { |folder| emptied?(folder, gone) && gone.add(folder) }
      end

      def removed(files) = candidates(files).select { |folder| remove(folder) }

      private

      def candidates(files)
        (@record.folders + files.flat_map { |file| @roots.parents(file) } + @roots.install_folders).uniq.sort_by { |folder| -folder.length }
      end

      def emptied?(folder, gone) = existing?(folder) && Dir.children(folder).all? { |name| gone.include?(File.join(folder, name)) }

      def existing?(folder) = @roots.inside?(folder) && File.directory?(folder)

      def remove(folder) = existing?(folder) && Dir.empty?(folder) && Dir.rmdir(folder).zero?
    end
  end
end
