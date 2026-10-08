# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # Reads one intent's spec.md: the goal lines, the done criteria and the
      # open decisions, each the lines or bullets under a heading. A bullet reads with its [ ] or [x]
      # prefix removed. A section that holds only "None" counts zero. No spec
      # row means no criteria and no decisions.
      class Spec
        # One done criterion: its key and its text.
        Criterion = Data.define(:key, :text) do
          def to_pair = [key, text]
        end

        DONE = /\A#+\s*(Done criteria|Acceptance Criteria|Acceptance)\s*\z/i
        OPEN = /\A#+\s*(Open Questions|Open decisions)\s*\z/i
        GOAL = /\A#+\s*Goals?\s*\z/i

        def initialize(retrieval, intent_id)
          document = retrieval.documents(intent_id).find { |candidate| candidate.path == "spec.md" }
          @lines = document ? document.body.lines.map(&:chomp) : []
          @present = [document].any?
        end

        def present? = @present

        def done_criteria = bullets_under(DONE)

        # Each done criterion with its key: the bracketed key that starts the
        # bullet, or the full text when the bullet carries none.
        def keyed_criteria = done_criteria.map { |text| Spec.criterion(text) }

        # Each done criterion's key mapped to its text; a criterion repeated word for word counts once.
        def criteria_by_key = keyed_criteria.uniq.to_h(&:to_pair)

        # The keys that name two different criteria.
        def key_clashes = keyed_criteria.uniq.group_by(&:key).select { |_key, same| same.size > 1 }.keys

        # Each line of the goal section, a bullet read without its dash.
        def goal_lines = section(GOAL).map { |line| Spec.bullet(line) || line.strip }.reject(&:empty?)

        def open_decisions = bullets_under(OPEN)

        BULLET = /\A[-*]\s*(?:\[[ xX]\]\s*)?(.+)\z/

        def self.bullet(line) = line[BULLET, 1]&.strip

        KEYED = /\A\[([a-z0-9][a-z0-9-]{1,31})\]\s+(.+)\z/

        def self.criterion(text)
          key, rest = text.match(KEYED)&.captures
          key ? Criterion.new(key:, text: rest) : Criterion.new(key: text, text:)
        end

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
