# frozen_string_literal: true

require "find"
require "fileutils"
require_relative "mirror"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class Preview
          class Changes
            def initialize(source, twin)
              @source = source
              @twin = twin
            end

            def call = (files(@source) | files(@twin)).sort.filter_map { |rel| line(rel) }

            private

            def files(root)
              return [] unless File.directory?(root)

              Find.find(root).select { |path| File.file?(path) && !path.match?(Mirror::DATABASE) && !path.match?(Mirror::SIDECAR) }.map { |path| path.delete_prefix("#{root}/") }
            end

            def line(rel)
              before = File.file?(File.join(@source, rel))
              after = File.file?(File.join(@twin, rel))
              return "would remove #{rel}" if before && !after
              return "would add #{rel}" if after && !before

              "would change #{rel}" if differs?(rel)
            end

            def differs?(rel)
              old = File.join(@source, rel)
              new = File.join(@twin, rel)
              !File.identical?(old, new) && !FileUtils.compare_file(old, new)
            end
          end
        end
      end
    end
  end
end
