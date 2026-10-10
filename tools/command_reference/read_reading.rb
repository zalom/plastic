# frozen_string_literal: true

module CommandReference
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
end
