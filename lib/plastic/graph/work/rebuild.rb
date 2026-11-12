# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      class StoreResume
        # The files of a store hold intents its rows lost.
        class Rebuild
          COMMAND = "plastic sync up --project %s"
          WHY = "the files hold intents the rows lost, and sync up reads every intent folder"

          def initialize(slug, folder)
            @slug = slug
            @folder = folder
          end

          def rows
            [["store:", @slug], ["rows:", "none; the files hold #{@folder.intent_dirs.size} intent folders"], ["then:", command]]
          end

          def next_step = [command, WHY]

          private

          def command = format(COMMAND, @slug)
        end
      end
    end
  end
end
