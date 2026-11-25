# frozen_string_literal: true

require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The files of the intent folders that the layout does not allow, found by a sync up and named in its output.
        # A file of an older layout is named with its repair; any other file is named as outside the layout. A sync up
        # reads none of them and changes none of them.
        class Strays
          def self.none = new([])

          # The strays of every intent folder of `folder`, a StoreFolder.
          def self.find(folder) = new(folder.intent_dirs.flat_map { |dir| in_dir(folder, dir) })

          def self.in_dir(folder, dir)
            rels = Dir.glob("**/*", File::FNM_DOTMATCH, base: folder.path(dir)).select { |rel| File.file?(folder.path("#{dir}/#{rel}")) }
            rels.select { |rel| stray?(rel) }.sort.map { |rel| "#{dir}/#{rel}" }
          end

          def self.stray?(rel) = !(Layout.read?(rel) || Layout.sorted?(rel) || Layout.machine?(rel))

          def initialize(paths)
            @paths = paths
          end

          def size = @paths.size

          # One line for each stray, in path order.
          def lines = @paths.map { |path| line(path) }

          private

          def line(path)
            entry = Layout.legacy_for(path.sub(%r{\Astore/[^/]+/}, ""))
            return "#{path} is not in the intent folder layout; plastic help intent-folder lists the files it allows" unless entry

            "#{path} is a file of an older layout: #{entry.repair}; plastic help intent-folder says why"
          end
        end
      end
    end
  end
end
