# frozen_string_literal: true

require_relative "../../../../layout"

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # The old actions folders of the repaired intent folders that hold nothing: the folders the repair emptied and the
          # ones that were empty already. A folder that holds a file stays.
          class EmptyFolders
            def initialize(folder)
              @folder = folder
            end

            def sweep(dirs) = dirs.each { |dir| remove("#{dir}/#{Layout.legacy_name(:actions).chomp("/")}") }

            private

            def remove(rel)
              path = @folder.path(rel)
              Dir.rmdir(path) if File.directory?(path) && Dir.empty?(path)
            end
          end
        end
      end
    end
  end
end
