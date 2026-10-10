# frozen_string_literal: true

module CommandReference
  # Lists every way one command can end, each with the line that decides it.
  class Endings
    NONE = "prints no next: line"
    RUNTIME = "decided at run time"

    def initialize(source)
      @source = source
    end

    def call(reach) = reach.endings(@source, rescued(reach))

    private

    def rescued(reach)
      return [] unless reach.raising?

      file = WorkflowReading::CODE_WORKFLOW
      [Ending.new(:rescue, 1, NONE, "a step raises", file, @source.find_line(file, /^\s*rescue => error/))]
    end
  end
end
