# frozen_string_literal: true

require "fileutils"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # The entries at the root of a store folder that the layout names as a leftover of an older release and marks
        # remove, such as roadmaps/, config.yml and resources/. A repair of every intent removes each one that exists.
        # An entry the layout marks keep or import stays, and an entry the layout does not name is left to the doctor.
        class RootLeftovers
          def initialize(folder)
            @folder = folder
          end

          # The names, relative to the store folder, that a repair removes; a folder ends with a slash.
          def removals = (@removals ||= Layout.store_root_legacy.select { |entry| entry.repair == "remove" }.map(&:name).select { |name| present?(name) })

          # An entry the layout does not name is left to the doctor, so a repair leaves no line about one.
          def left = []

          def preview = removals.map { |name| "preview: remove #{name}" }

          def call
            removals.each { |name| FileUtils.rm_rf(@folder.path(name.chomp("/"))) }
            removals.map { |name| "removed #{name}" }
          end

          private

          # A name with a closing slash names a folder, and any other name a file.
          def present?(name)
            path = @folder.path(name.chomp("/"))
            name.end_with?("/") ? File.directory?(path) : File.file?(path)
          end
        end
      end
    end
  end
end
