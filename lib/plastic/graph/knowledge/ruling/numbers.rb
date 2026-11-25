# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Ruling
        # The numbers the decisions of one intent have held: the ids of its rulings and the ids its ruled work log lines
        # begin with. No number is used twice, so a new decision takes the whole number after the highest one held, and an
        # addition the number after the highest addition of its decision held, even when a fold or a rewrite removed it.
        class Numbers
          ID = /\AD(\d+)(?:\.(\d+))?(?![.\w])/
          WHOLE = /\AD\d+\z/

          # Whether `id` names a whole decision, such as D1, and not an addition, such as D1.1.
          def self.whole?(id) = id.match?(WHOLE)

          # The numbers of `rulings` and of the ruled lines of `log`.
          def self.of(rulings, log) = new(rulings.map(&:id) + log.select { |line| line.kind == "ruled" }.map(&:text))

          # The whole number and the addition number `id` begins with, such as [1, 2] for D1.2 and [1, nil] for D1.
          def self.parts(id) = ID.match(id)&.captures&.map { |part| part&.to_i }

          def self.highest(numbers) = numbers.max || 0

          # `ids` are ids, or texts that begin with one.
          def initialize(ids)
            @held = ids.filter_map { |id| Numbers.parts(id) }
          end

          def next_whole = "D#{Numbers.highest(@held.map(&:first)) + 1}"

          # The next addition of the whole decision `whole`, such as D1.3 under D1.
          def next_addition(whole)
            number = whole.delete_prefix("D").to_i
            "#{whole}.#{Numbers.highest(@held.filter_map { |held, addition| addition if held == number }) + 1}"
          end
        end
      end
    end
  end
end
