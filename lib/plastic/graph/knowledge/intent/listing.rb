# frozen_string_literal: true

require_relative "../intent"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # How a list of intents reads by group: each non-empty group with at most MAX of its intents and how many more it holds.
        module Listing
          MAX = 10

          # One group: its name, the intents shown and the count left out.
          Group = Data.define(:name, :shown, :rest) do
            def pairs(&) = [*shown.map(&), *("and #{rest} more" if rest.positive?)].map { |text| [name, text] }
          end

          module_function

          def group_of(status) = GROUPS.find { |_name, states| states.include?(status) }.first

          def of(intents)
            members = intents.group_by { |intent| group_of(intent.status) }
            GROUPS.keys.filter_map { |name| window(name, members.fetch(name, [])) }
          end

          def lines(intents, &) = of(intents).flat_map { |group| group.pairs(&) }

          def window(name, members) = (Group.new(name, members.first(MAX), [members.size - MAX, 0].max) if members.any?)
        end
      end
    end
  end
end
