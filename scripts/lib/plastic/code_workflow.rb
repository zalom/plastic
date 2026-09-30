# frozen_string_literal: true

require_relative "workflow"
require_relative "failed"
require_relative "refused"

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
    Gate = Data.define(:reason, :stops, :pass) do
      def name = "gate"
    end
    Read = Data.define(:name, :body)
    Step = Data.define(:name, :done, :body)

    # How a gate stops the call: exit 3 or exit 1.
    STOPS = %i[refusal failure].freeze

    class << self
      def lane = "code"

      def steps = (@steps ||= [])

      # A check that stops the call when pass: is false, and prints `reason`.
      # stops: :refusal ends in exit 3 and names an owner step. stops:
      # :failure ends in exit 1 and names something the agent can fix.
      def gate(reason, stops:, pass:)
        raise Invalid, "#{name}: a gate stops as :refusal or :failure" unless STOPS.include?(stops)

        steps << Gate.new(reason, stops, pass)
      end

      # A step that changes nothing on disk. It runs on every call, rerun
      # included, because doing it twice changes nothing.
      def read(name, &body)
        steps << Read.new(name, body)
      end

      # A step that changes state. It runs only while its done: check is
      # false, and the check must hold after the body. So a rerun after a
      # failure or a handoff never repeats the change.
      def step(name, done:, &body)
        raise Invalid, "#{self.name}: step #{name.inspect} needs a block" unless body

        steps << Step.new(name, done, body)
      end

      # The first outcome whose if: holds is returned. A line with no if: is
      # the fallback, and it comes last. A workflow with no outcome line has
      # one outcome, :done.
      def outcome(name, **options)
        fallback = outcomes.find { |o| o.check.nil? }
        raise Invalid, "#{self.name}: outcome #{name} follows the fallback #{fallback.name}" if fallback
        raise Invalid, "#{self.name}: outcome #{name} takes no stops:; a gate stops the call" if options.key?(:stops)

        super
      end

      def outcome_names = outcomes.empty? ? [:done] : outcomes.map(&:name)

      def templates = super + steps.grep(Gate).map(&:reason)

      def problems
        return [] if outcomes.empty? || outcomes.last.check.nil?

        ["#{key}: the last outcome line needs no if:, so that one outcome always holds"]
      end
    end

    def call
      self.class.steps.each do |step|
        stop = perform(step)
        return stop if stop
      end
      pick
    end

    private

    # Nil when the step is done with; otherwise the value that ends the call.
    def perform(step)
      case step
      in Gate then check(step)
      in Read then observe(step)
      else change(step)
      end
    rescue => e
      Failed.new(key, step.name, "#{e.class}: #{e.message}")
    end

    def check(gate)
      return nil if gate.pass.call(ctx)

      reason = ctx.fill(gate.reason)
      (gate.stops == :refusal) ? Refused.new(key, reason) : Failed.new(key, gate.name, reason)
    end

    def observe(read)
      read.body.call(ctx)
      nil
    end

    def change(step)
      return nil if step.done.call(ctx)

      step.body.call(ctx)
      step.done.call(ctx) ? nil : Failed.new(key, step.name, "the step ran and its done check still fails")
    end

    def pick
      return :done if self.class.outcomes.empty?

      self.class.outcomes.find { |o| o.check.nil? || o.check.call(ctx) }.name
    end
  end
end
