# frozen_string_literal: true

module CommandReference
  # Picks the reader for each kind of step.
  module StepReadings
    def self.reader(step)
      kinds = { Plastic::CodeWorkflow::Gate => GateReading, Plastic::CodeWorkflow::Read => ReadReading, Plastic::CodeWorkflow::Step => StepReading }
      kinds.find { |type, _| step.is_a?(type) }&.last || AgentReading
    end
  end

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

  # A read read into a row.
  class ReadReading
    FORGET = "forget a stop of an earlier call"

    def initialize(read, owner)
      @read = read
      @owner = owner
    end

    def row
      name = @read.name
      file, line = forgotten || @owner.at(@read.body, "read") || @owner.named("read", name)
      Row.new(:read, name, nil, nil, nil, file, line)
    end

    private

    def forgotten
      return unless @read.name == FORGET

      [WorkflowReading::CODE_WORKFLOW, @owner.source.find_line(WorkflowReading::CODE_WORKFLOW, /^\s*def forget_stop\b/)]
    end
  end

  # A code step read into a row.
  class StepReading
    def initialize(step, owner)
      @step = step
      @owner = owner
    end

    def row
      name = @step.name
      file, line = @owner.at(@step.body, "step") || @owner.named("step", name)
      Row.new(:step, name, @owner.source.lambda_code(@step.done), :failure, nil, file, line)
    end
  end

  # An agent step read into a row.
  class AgentReading
    def initialize(step, owner)
      @step = step
      @owner = owner
    end

    def row
      name = @step.name
      file, line = @owner.named("step", name)
      Row.new(:agent, name, @owner.source.lambda_code(@step.done), nil, @step.say, file, line)
    end
  end

  # An outcome line of a workflow read into an Outcome.
  class OutcomeReading
    def initialize(name, owner)
      @name = name
      @owner = owner
      @line = owner.workflow.outcomes.find { |found| found.name == name }
    end

    def outcome
      Outcome.new(@name, @owner.source.lambda_code(@line&.check), fallback?, @line&.offers, @line&.because, target, exit_code, *place)
    end

    private

    def handoff? = @owner.workflow.lane == "agent" && @name == :handoff

    def fallback? = @owner.workflow.lane == "code" && (@line ? @line.fallback? : true)

    def target = handoff? ? :noop : @owner.next_key(@name)

    def exit_code = handoff? ? @owner.workflow.handoff_exit_code : 0

    def place = @owner.at(@line&.check, "outcome") || @owner.named("outcome", @name) || @owner.first("outcome")
  end
end
