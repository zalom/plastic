# frozen_string_literal: true

require_relative "workflow"
require_relative "errors"
require_relative "code_workflow/gate"
require_relative "code_workflow/read"
require_relative "code_workflow/step"

module Plastic
  # A workflow of Ruby steps. The steps run in order, each one once per
  # call, and then the first outcome whose if: holds is returned.
  #
  #   gate     stops the call unless its pass: check holds
  #   read     reads, sets facts, or prints; it changes nothing on disk
  #   step     changes state; its done: check makes a rerun skip it
  #   outcome  one way the workflow ends
  #
  # A block does the work. A keyword lambda (done:, pass:, if:) answers a
  # question and changes nothing.
  class CodeWorkflow < Workflow
    # How a gate stops the call: exit 3 or exit 1.
    STOPS = %i[refusal failure].freeze
    GATE_OPTIONS = %i[stops pass offers because words].freeze

    class << self
      def lane = "code"

      def steps = (@steps ||= [])

      # A check that stops the call when pass: is false, and prints `reason`.
      # stops: :refusal ends in exit 3 and names an owner step. stops:
      # :failure ends in exit 1 and names something the agent can fix.
      # because: is the line that says why; the reason serves when it is left out.
      def gate(reason, **rule)
        unknown = rule.keys - GATE_OPTIONS
        raise Invalid, "#{name}: unknown gate option #{unknown.join(", ")}" if unknown.any?

        stops = rule.fetch(:stops)
        raise Invalid, "#{name}: a gate stops as :refusal or :failure" unless STOPS.include?(stops)

        steps << Gate.new(reason, stops, rule.fetch(:pass), *rule.values_at(:offers, :because, :words))
      end

      # A step that changes nothing on disk. It runs on every call, rerun
      # included, because doing it twice changes nothing.
      def read(step_name, &body)
        steps << Read.new(step_name, body)
      end

      # A read that clears what a stopped step of an earlier call left in
      # `names`, so a resumed command run tries that step again rather than
      # replaying its stop. An earlier call stopped when `problem` is set.
      def forget_stop(*names)
        read("forget a stop of an earlier call") do |context|
          clear_facts(context, names) if context.problem
        end
      end

      def clear_facts(context, names) = names.each { |name| context[name] = nil }

      # A step that changes state. It runs only while its done: check is
      # false, and the check must hold after the body. So a rerun after a
      # failure or a handoff never repeats the change.
      def step(step_name, done:, changes: nil, &body)
        label = step_name.inspect
        raise Invalid, "#{name}: step #{label} needs a block" unless body
        raise Invalid, "#{name}: step #{label} needs changes:, a hash of place to words, or {} when it changes nothing" unless changes

        steps << Step.new(step_name, done, changes, body)
      end

      # The first outcome whose if: holds is returned. A line with no if: is
      # the fallback, and it comes last. A workflow with no outcome line has
      # one outcome, :done.
      def outcome(outcome_name, **options)
        fallback = outcomes.find(&:fallback?)
        raise Invalid, "#{name}: outcome #{outcome_name} follows the fallback #{fallback.name}" if fallback
        raise Invalid, "#{name}: outcome #{outcome_name} takes no stops:; a gate stops the call" if options.key?(:stops)

        super
      end

      def outcome_names = outcomes.empty? ? [:done] : outcomes.map(&:name)

      def templates = super + steps.grep(Gate).flat_map(&:templates)

      def problems
        return [] if outcomes.empty? || outcomes.last.fallback?

        ["#{key}: the last outcome line needs no if:, so that one outcome always holds"]
      end

      def clear_declarations
        super
        steps.clear
      end
    end

    def call = self.class.steps.lazy.filter_map { |step| perform(step) }.first || pick

    private

    def perform(step)
      step.call(ctx, self.class)
    rescue Usage, Failed, Refused
      raise
    rescue => error
      raise Failed.raised(key, step.name, error)
    end

    def pick
      outcomes = self.class.outcomes
      outcomes.empty? ? :done : outcomes.find { |outcome| outcome.holds?(ctx) }.name
    end
  end
end
