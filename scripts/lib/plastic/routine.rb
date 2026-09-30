# frozen_string_literal: true

require_relative "cli/command"
require_relative "invalid"
require_relative "finished"
require_relative "handed_off"
require_relative "failed"
require_relative "refused"
require_relative "context"
require_relative "routine_run"
require_relative "routine/chain"
require_relative "workflow"
require_relative "graph"

module Plastic
  # A tool whose work is a chain of workflows. The chain is data: each
  # `workflow` line names a key and where each outcome goes next.
  #
  #   workflow :code_check_write_lock, next: :code_check_ending
  #   workflow :code_check_ending do
  #     on :written, next: :code_close_intent
  #     on :missing, next: :agent_write_outcome
  #   end
  #
  # :noop ends the chain. The workflow that ends it supplies next: and
  # because: through its `outcome` lines. Routine::Chain holds the keys and
  # edges and checks them.
  class Routine < CLI::Command
    class << self
      def workflow(key, **edge, &branches)
        chain.add(key, edge[:next], &branches)
      end

      def chain = (@chain ||= Chain.new(self))

      # The namespace that holds the chain's workflows and their REGISTRY.
      def workflows = Workflows

      # Every name a step may read or write: the tool's arguments and options,
      # plus the facts each workflow in the chain declares.
      def declared_facts
        arguments.map(&:name) + options.map(&:name) + chain.facts
      end

      # Runs once per process, on the first call, and raises every problem at
      # once, so a reordered chain never skips a workflow in silence.
      def verify!
        @verified ||= begin
          problems = chain_problems
          raise Invalid, "#{name}: #{problems.join("; ")}" if problems.any?

          true
        end
      end

      def chain_problems = chain.problems(arguments.map(&:name) + options.map(&:name))
    end

    def call
      self.class.verify!
      routine_run = open_routine_run
      ctx = context(routine_run)
      value = walk(ctx)
      routine_run.close(value, ctx.facts)
      save_routine_run(routine_run)
      report(value, ctx)
    rescue Graph::Database::Error => e
      raise CLI::Command::Failure, e.message
    end

    private

    # A resumed routine run brings back what its workflows found; this call's
    # arguments and options always win, nil included.
    def context(routine_run)
      Context.new(declared: self.class.declared_facts, facts: routine_run.facts.merge(parsed),
        graphs:, routine_run:, session:)
    end

    def walk(ctx)
      key = chain.entry
      loop do
        workflow = chain.fetch(key)
        outcome = workflow.call(ctx)
        return outcome unless outcome.is_a?(Symbol)

        key = chain.target(workflow.key, outcome)
        save_routine_run(ctx.routine_run.advance(workflow.key, key))
        return closed(workflow, outcome, ctx) if key == :noop
      end
    end

    def chain = self.class.chain

    def closed(workflow, outcome, ctx)
      command, because = workflow.closing(outcome, ctx)
      Finished.new(next_command: command, because:)
    rescue => e
      Failed.new(workflow.key, "closing", "#{e.class}: #{e.message}")
    end

    # The printed lines go first on every end, failure included, so a gate
    # that says "see above" has something above it. Then the call says what
    # it wrote: the rows, one phrase per database. The end value prints its
    # own last lines and gives the exit code.
    #
    #   wrote: 1 intent and 1 ledger line in work_graph.db
    def report(value, ctx)
      ctx.printed.each { |line| output.raw(line) }
      output.row("wrote:", graphs.wrote)
      @exit_code = value.report(output)
    end

    # The open routine run for this tool and subject, or a new one. Only a
    # tool that writes keeps its routine run as a row.
    def open_routine_run
      found = graphs.retrieval.routine_run(words, subject) if keeps_routine_run?
      found&.open? ? found : RoutineRun.fresh(words, subject)
    end

    # The subject arguments of this call, joined, or nil when none is set.
    def subject
      parts = Array(self.class.subject).filter_map { |name| parsed[name] }
      parts.join("-") unless parts.empty?
    end

    def save_routine_run(routine_run)
      graphs.work.save_routine_run(routine_run) if keeps_routine_run?
    end

    def keeps_routine_run? = self.class.writes.any?
  end
end
