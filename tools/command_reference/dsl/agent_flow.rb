# frozen_string_literal: true

module CommandReference
  module Dsl
    # An agent workflow beside what a call prints for each step.
    class AgentFlow < CodeFlow
      NOTES = {
        "step" => Note.new(nil, "STEP", ["printed while its done: check fails"], "lane-agent", "tag tag-agent")
      }.freeze

      def self.outcome(text) = Note.new(nil, "OUTCOME", [text.include?(":handoff") ? "ends the call while a step is left" : "ends the call once every check holds"], "end", "tag tag-end")

      private

      def table = NOTES
    end
  end
end
