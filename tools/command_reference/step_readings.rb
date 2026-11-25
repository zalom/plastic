# frozen_string_literal: true

module CommandReference
  # Picks the reader for each kind of step.
  module StepReadings
    def self.reader(step)
      kinds = { Plastic::CodeWorkflow::Gate => GateReading, Plastic::CodeWorkflow::Read => ReadReading, Plastic::CodeWorkflow::Step => StepReading }
      kinds.find { |type, _| step.is_a?(type) }&.last || AgentReading
    end
  end
end
