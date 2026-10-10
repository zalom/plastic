# frozen_string_literal: true

module CommandReference
  # A gate read into a row.
  class GateReading
    def initialize(gate, owner)
      @gate = gate
      @owner = owner
    end

    def row = Row.new(:gate, @gate.reason, @owner.source.lambda_code(@gate.pass), @gate.stops, nil, *place)

    private

    def place = @owner.at(@gate.pass, "gate") || by_method || by_reason || @owner.first("gate")

    def by_method
      pass = @gate.pass
      @owner.search(/^\s*gate\b.*method\(:#{pass.name}\)/) if pass.is_a?(Method)
    end

    def by_reason
      reason = @gate.reason
      alternatives = [Regexp.escape(reason.inspect), *@owner.holders(reason).map { |name| "\\b#{name}\\b" }]
      @owner.search(/^\s*gate\b.*(?:#{alternatives.join("|")})/)
    end
  end
end
