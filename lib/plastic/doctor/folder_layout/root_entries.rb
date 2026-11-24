# frozen_string_literal: true

require_relative "../../layout"

module Plastic
  module Doctor
    class FolderLayout
      # The entries at the root of a store folder that the layout neither allows there nor names as a leftover of an
      # older release, each with a closing slash when it is a folder. A database name such as *.db names its journal
      # files too. Machine state, such as .DS_Store, is no entry. It reads the folder and writes nothing.
      class RootEntries
        JOURNAL = /-(?:wal|shm|journal)\z/

        def initialize(root)
          @root = root
          @names = [*Layout.store_root_allowed, *Layout.store_root_legacy].map(&:name)
        end

        def to_a
          return [] unless File.directory?(@root)

          Dir.children(@root).sort.reject { |name| name.match?(Layout.skipped) || named?(name) }.map { |name| shown(name) }
        end

        private

        def named?(name) = @names.any? { |pattern| names?(pattern, name) }

        # Whether the layout name `pattern` names the entry `name`: a name with a closing slash names a folder, and any
        # other name a file, by its pattern.
        def names?(pattern, name)
          folder = folder?(name)
          return folder && pattern.chomp("/") == name if pattern.end_with?("/")

          !folder && File.fnmatch?(pattern, name.sub(JOURNAL, ""), File::FNM_DOTMATCH)
        end

        def folder?(name) = File.directory?(File.join(@root, name))

        def shown(name) = folder?(name) ? "#{name}/" : name
      end
    end
  end
end
