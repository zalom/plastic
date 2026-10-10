# frozen_string_literal: true

module Plastic
  class CLI
    class Screen
      # One item of the list, and whether it starts picked.
      Choice = Data.define(:label, :chosen) do
        # The numbers of the items that start picked, counted from one.
        def self.preselected(choices) = choices.each.with_index(1).filter_map { |choice, number| number if choice.chosen }

        def numbered(number) = "#{number}  [#{chosen ? "x" : " "}] #{label}"
      end

      # The person picked these labels, in list order.
      Chosen = Data.define(:labels)

      # The person left with no change.
      Left = Data.define

      # The list is printed for the person and the call stops.
      Listed = Data.define
    end
  end
end
