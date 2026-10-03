# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # Reads one intent's spec.md: the goal lines, the done criteria and the
      # open decisions, each the lines or bullets under a heading. A bullet reads with its [ ] or [x]
      # prefix removed. A section that holds only "None" counts zero. No spec
      # row means no criteria and no decisions.
      class Spec
        DONE = /\A#+\s*(Done criteria|Acceptance Criteria|Acceptance)\s*\z/i
        OPEN = /\A#+\s*(Open Questions|Open decisions)\s*\z/i
        GOAL = /\A#+\s*Goals?\s*\z/i

        def initialize(retrieval, intent_id)
          document = retrieval.documents(intent_id).find { |candidate| candidate.path == "spec.md" }
          @lines = document ? document.body.lines.map(&:chomp) : []
        end

        def done_criteria = bullets_under(DONE)

        # Each line of the goal section, a bullet read without its dash.
        def goal_lines = section(GOAL).map { |line| Spec.bullet(line) || line.strip }.reject(&:empty?)

        def open_decisions = bullets_under(OPEN)

        BULLET = /\A[-*]\s*(?:\[[ xX]\]\s*)?(.+)\z/

        def self.bullet(line) = line[BULLET, 1]&.strip

        private

        def bullets_under(heading)
          section(heading).filter_map { |line| Spec.bullet(line) }.reject { |item| item.casecmp("none").zero? }
        end

        def section(heading)
          start = @lines.index { |line| line.match?(heading) }
          return [] unless start

          @lines[(start + 1)..].take_while { |line| !line.match?(/\A#+\s/) }
        end
      end
    end
  end
end
