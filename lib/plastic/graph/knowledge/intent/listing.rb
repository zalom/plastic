# frozen_string_literal: true

require_relative "../intent"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # How a list of intents reads by group: each non-empty group with at most MAX of its intents and how many more it holds.
        module Listing
          MAX = 10

          module_function

          def of(intents)
            members = intents.group_by(&:group)
            GROUPS.keys.filter_map { |name| window(name, members[name]) if members[name] }
          end

          def window(name, members) = [name, members.first(MAX), [members.size - MAX, 0].max]
        end
      end
    end
  end
end
