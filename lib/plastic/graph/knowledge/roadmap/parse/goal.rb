# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The "## Goal" section: its lines, joined into one text.
          class Goal
            def initialize
              @lines = []
            end

            def line(text, _number) = (@lines << text unless text.strip.empty?)

            def finish = nil

            def text = @lines.join(" ").strip.empty? ? nil : @lines.map(&:strip).join(" ")
          end
        end
      end
    end
  end
end
