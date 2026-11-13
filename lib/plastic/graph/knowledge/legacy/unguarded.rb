# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # A rollback guard that runs its block with no protection.
        class Unguarded
          def initialize(_root)
          end

          def call = yield
        end
      end
    end
  end
end
