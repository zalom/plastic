# frozen_string_literal: true

require_relative "../down"
require_relative "../up/preview"

module Plastic
  module Workflows
    module Code
      module Sync
        class Down
          # Previews sync down in a copy before the normal write workflow.
          class Preview < Up::Preview
            [facts, steps, outcomes].each(&:clear)
            preview :down
          end
        end
      end
    end
  end
end
