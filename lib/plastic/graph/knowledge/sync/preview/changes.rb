# frozen_string_literal: true

require "fileutils"
require_relative "tree"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class Preview
          # The paths a preview would add, remove or change, by comparing the store with its twin.
          class Changes
            def initialize(source, twin)
              @source = source
              @twin = twin
            end

            def call = (Tree.new(@source).files | Tree.new(@twin).files).sort.filter_map { |rel| line(rel) }

            private

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
