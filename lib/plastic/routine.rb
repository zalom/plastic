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
require_relative "routine/traversal"
require_relative "routine/preview"
require_relative "routine/printing"
require_relative "routine/graph_report"
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
  # edges and checks them; Routine::Traversal walks them.
  class Routine < CLI::Command
    extend Preview::Declaration
    include Preview
    include Printing
    include GraphReport

    class << self
      def workflow(key, **edge, &branches)
        chain.add(key, edge[:next], &branches)
      end

      def chain = (@chain ||= Chain.new(self))

      # The namespace that holds the chain's workflows and their REGISTRY.
      def workflows = Workflows

      # Every name a step may read or write: the tool's arguments and options,
      # plus the facts each workflow in the chain declares.
      def declared_facts = declared_names + chain.facts

      # Runs once per process, on the first call, and raises every problem at
      # once, so a reordered chain never skips a workflow in silence.
      def verify
        @verified ||= begin
          problems = chain_problems
          raise Invalid, "#{name}: #{problems.join("; ")}" if problems.any?

          true
        end
      end

      def chain_problems = chain.problems(declared_names) + preview_problems
    end

    def call
      self.class.verify
      previewing? ? preview : run_chain
    end

    private

    def finish(routine_run)
      ctx = context(routine_run)
      traversal = Traversal.new(chain, ctx, routine_run) { |run| save_routine_run(run) }
      report(traversal.call { |value| printing(value, ctx) }, ctx)
    end

    # A resumed routine run brings back what its workflows found; this call's
    # arguments and options always win, nil included.
    def context(routine_run)
      Context.new(declared: self.class.declared_facts, facts: routine_run.facts.merge(parsed).merge(preview_facts), graphs: routine_graphs, harness: Context::Harness.new(environment.session, scope))
    end

    def chain = self.class.chain

    # The printed lines and rows go first on every end, failure included, so a gate
    # that says "see above" has something above it. Then the call says what
    # it wrote: the rows, one phrase per database, and the files it
    # printed. The end value prints its own last lines and gives the exit code.
    #
    #   wrote: 1 intent and 1 ledger line in work_graph.db
    def report(value, ctx)
      ctx.print_to(output)
      report_graphs if touches_graphs?
      @exit_code = value.report(output)
    end

    # The open routine run for this tool and subject, or a new one.
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

    # A command that writes keeps its routine run, so a resumed write finds
    # its facts. A read, and a dry run, keep none.
    def keeps_routine_run? = self.class.writes.any? && !parsed[:dry_run]
  end
end
