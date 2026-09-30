# frozen_string_literal: true

require_relative "workflow"
require_relative "failed"
require_relative "handed_off"
require_relative "agent_workflow/step"

module Plastic
  # A workflow of plain-word steps that the agent does. A call prints the
  # steps whose done: check fails and hands over; the next call checks them
  # again. So an agent workflow always ends the chain.
  #
  #   step     one thing the agent does, said in words
  #   outcome  :handoff while a step is left, :done once every check holds
  class AgentWorkflow < Workflow
    OUTCOMES = %i[handoff done].freeze

    class << self
      def lane = "agent"

      def steps = (@steps ||= [])

      # `say:` is a String with %{fact} names. `done:` reads the graphs: the
      # agent reports its work through a Plastic tool, and the next call sees
      # the record.
      def step(step_name, done:, say:)
        steps << Step.new(step_name, done, say)
      end

      # The kernel picks the outcome, so an agent's outcome line takes no if:.
      # stops: :failure makes the handoff exit 1: the call did not do its
      # job, and the steps say how to fix that.
      def outcome(outcome_name, **options)
        raise Invalid, "#{name}: an agent workflow ends on #{OUTCOMES.join(" or ")}" unless OUTCOMES.include?(outcome_name)
        raise Invalid, "#{name}: the kernel picks an agent's outcome, so #{outcome_name} takes no if:" if options.key?(:if)
        if options.key?(:stops) && [outcome_name, options[:stops]] != %i[handoff failure]
          raise Invalid, "#{name}: only the handoff stops, and only as :failure"
        end

        super
      end

      def outcome_names = OUTCOMES

      def templates = super + steps.map(&:say)

      def handoff_exit_code = (ending(:handoff).stops == :failure) ? 1 : 0
    end

    def call
      left = steps_left
      left.empty? ? :done : hand_off(left)
    rescue => error
      Failed.raised(key, "handoff", error)
    end

    private

    def steps_left = self.class.steps.select { |step| step.left?(ctx) }

    def hand_off(left)
      workflow = self.class
      command, because = workflow.closing(:handoff, ctx)
      HandedOff.new(steps: left.map { |step| step.instruction(ctx) }, next_command: command, because:,
        exit_code: workflow.handoff_exit_code)
    end
  end
end
