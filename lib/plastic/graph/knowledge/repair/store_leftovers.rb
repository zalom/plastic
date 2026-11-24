# frozen_string_literal: true

require "fileutils"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # The entries of the folder store/ of a store folder that the layout does not allow beside the intent folders. A
        # leftover that the layout removes goes; a database is removed only when it is empty, and named and left when it
        # holds data. An entry the layout does not name is named and left. Machine state, such as .DS_Store, is no entry.
        class StoreLeftovers
          ROOT = "store"
          HOLDS_DATA = "it holds data"
          UNNAMED = "the layout does not name it"

          def initialize(folder)
            @folder = folder
          end

          # The paths, relative to the store folder, that a repair removes; a folder ends with a slash.
          def removals = (@removals ||= entries.filter_map { |name, entry| shown(name) if entry && removable?(name, entry) })

          # One line for each entry a repair leaves although the layout does not allow it.
          def left = entries.filter_map { |name, entry| left_line(name, entry) }

          def preview = removals.map { |rel| "preview: remove #{rel}" }

          def call
            removals.each { |rel| FileUtils.rm_rf(@folder.path(rel)) }
            [*removals.map { |rel| "removed #{rel}" }, *left]
          end

          private

          # Each entry of store/ that the layout does not allow, with the legacy entry that names it, or nil.
          def entries
            names = File.directory?(@folder.path(ROOT)) ? Dir.children(@folder.path(ROOT)).sort : []
            names.reject { |name| allowed?(name) || name.match?(Layout.skipped) }.map { |name| [name, legacy(name)] }
          end

          def left_line(name, entry)
            return "left #{shown(name)}: #{UNNAMED}" unless entry

            "left #{shown(name)}: #{HOLDS_DATA}" unless removable?(name, entry)
          end

          def allowed?(name) = Layout.store_folder_allowed.any? { |entry| named?(entry.name, name) }

          def legacy(name) = Layout.store_folder_legacy.find { |entry| named?(entry.name, name) }

          def removable?(name, entry) = entry.repair == "remove" || File.zero?(path(name))

          # Whether the layout name `pattern` names the entry `name`: a name with a closing slash names a folder, and the
          # intent folder template names any folder `{id}--{slug}`.
          def named?(pattern, name)
            folder = pattern.end_with?("/")
            return false unless folder == File.directory?(path(name))

            bare = pattern.chomp("/")
            (bare == Layout.folder_template) ? name.include?("--") : bare == name
          end

          def path(name) = @folder.path("#{ROOT}/#{name}")

          def shown(name) = File.directory?(path(name)) ? "#{ROOT}/#{name}/" : "#{ROOT}/#{name}"
        end
      end
    end
  end
end
