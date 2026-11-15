# frozen_string_literal: true

module CommandReference
  # An outcome line of a workflow read into an Outcome.
  class OutcomeReading
    def initialize(name, owner)
      @name = name
      @owner = owner
      @line = owner.workflow.outcomes.find { |found| found.name == name }
    end

    def outcome
      Outcome.new(@name, @owner.source.lambda_code(@line&.check), fallback?, @line&.offers, words, target, exit_code, *place, @line&.found_by, @line&.unreachable)
    end

    private

    def words = (@line.ends_when if @line&.because.to_s.match?(PageWords::PLACEHOLDER)) || @line&.because

    def handoff? = @owner.workflow.lane == "agent" && @name == :handoff

    def fallback? = @owner.workflow.lane == "code" && (@line ? @line.fallback? : true)

    def target = handoff? ? :noop : @owner.next_key(@name)

    def exit_code = handoff? ? @owner.workflow.handoff_exit_code : 0

    def place = @owner.at(@line&.check, "outcome") || @owner.named("outcome", @name) || @owner.first("outcome")
  end
end
