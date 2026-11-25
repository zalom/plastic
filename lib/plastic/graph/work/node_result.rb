# frozen_string_literal: true

require_relative "../../errors"
require_relative "../knowledge/legacy_path"
require_relative "../../layout"

module Plastic
  module Graph
    module Work
      # The files of an intent folder that a node move reads as its result: the files named, or every file the sync
      # selection reads, that changed since they were last printed. The files the rows print are never a result.
      class NodeResult
        PRINTED_BY_ROWS = [Layout.name(:graph), Layout.name(:context), Layout.name(:log)].freeze

        def initialize(folder, retrieval)
          @folder = folder
          @retrieval = retrieval
        end

        def paths(intent_id, named)
          dir = @retrieval.intent(intent_id)&.dir
          return [] unless dir

          printed = @retrieval.stored.printed
          candidates(dir, named).select { |path| result?(dir, path) && @folder.digest(path) != printed[path] }
        end

        private

        def candidates(dir, named) = named.empty? ? @folder.files(dir) : named.map { |name| read_by_sync(dir, name) }

        def read_by_sync(dir, name)
          path = inside(dir, name)
          raise Usage, "#{name} is not read by the sync, so it cannot be the result of a node" unless result?(dir, path)

          path
        end

        def inside(dir, name)
          path = name.start_with?("#{dir}/") ? name : File.join(dir, name)
          base = File.expand_path(@folder.path(dir))
          full = File.expand_path(@folder.path(path))
          raise Usage, "#{name} is not a file of the intent folder #{dir}" unless full.start_with?("#{base}/") && @folder.exist?(path)

          full.delete_prefix("#{File.expand_path(@folder.root)}/")
        end

        def result?(dir, path)
          rel = path.delete_prefix("#{dir}/")
          !PRINTED_BY_ROWS.include?(rel) && !Knowledge::LegacyPath.legacy?(rel) && @folder.sync.selection.read?(rel, intent_id: Knowledge::SyncSelection.intent_of(dir))
        end
      end
    end
  end
end
