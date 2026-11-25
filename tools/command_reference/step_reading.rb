# frozen_string_literal: true

module CommandReference
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
end
