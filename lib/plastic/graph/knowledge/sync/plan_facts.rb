# frozen_string_literal: true

require_relative "archived_intents"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # What a sync reads from the folder and the resolution before it plans any entry: an import
        # waiting, a call that cannot run, and the archived intents with no row.
        class PlanFacts
          def initialize(folder, retrieval, resolution)
            @folder = folder
            @retrieval = retrieval
            @resolution = resolution
          end

          def importing? = @folder.legacy? && @resolution.up?

          def problem = (legacy_problem if @folder.legacy? && !@resolution.up?)

          def archived = (@resolution.up? && !@folder.legacy?) ? ArchivedIntents.new(@folder, @retrieval).missing.size : 0

          private

          def legacy_problem = "this store still has #{StoreFolder::LEGACY_INDEX}; run plastic sync up to import it first"
        end
      end
    end
  end
end
