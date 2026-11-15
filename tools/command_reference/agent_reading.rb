# frozen_string_literal: true

module CommandReference
  # An agent step read into a row.
  class AgentReading
    def initialize(step, owner)
      @step = step
      @owner = owner
    end

    def row
      name = @step.name
      file, line = @owner.named("step", name)
      Row.new(:agent, name, @owner.source.lambda_code(@step.done), nil, words, file, line)
    end

    private

    def words = (@step.gets if @step.say.match?(PageWords::PLACEHOLDER)) || @step.say
  end
end
