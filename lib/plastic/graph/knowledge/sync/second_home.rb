# frozen_string_literal: true

require_relative "../store_folder"
require_relative "archived_intents"
require_relative "second_home/contexts"
require_relative "second_home/clusters"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The files a second home reads on its first sync up, because it holds no rows for what they carry: the
        # context.json of an intent that holds no context and no
        # discovery. A part that cannot be read is a broken part, named by its path and left as it is; every good part is read.
        class SecondHome
          def initialize(folder, retrieval, folders = nil)
            @folder = folder
            @retrieval = retrieval
            @folders = folders
          end

          # The home of a sync that reads nothing: no file to read and no part that cannot be.
          class Idle
            def problems = {}

            def paths = []

            def size = 0
          end

          NONE = Idle.new

          # Each part that cannot be read, by path, with the reason.
          def problems = (@problems ||= contexts.problems.merge(clusters.problems))

          # The paths the reader turns into rows: context.json files.
          def paths = contexts.paths

          def size = paths.size

          private

          def contexts = Contexts.new(@folder, @retrieval, @folders, known)

          def clusters = Clusters.new(@folder, @retrieval, known)

          def known
            @known ||= [*@retrieval.intents.map(&:intent_id), *Array(@folders&.intents).map(&:intent_id),
              *ArchivedIntents.new(@folder, @retrieval).missing.map { |mark| mark["intent_id"] }]
          end
        end
      end
    end
  end
end
