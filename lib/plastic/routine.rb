# frozen_string_literal: true

require_relative "cli/command"
require_relative "invalid"
require_relative "finished"
require_relative "handed_off"
require_relative "errors"
require_relative "context"
require_relative "command_run"
require_relative "routine/chain"
require_relative "routine/traversal"
require_relative "routine/preview"
require_relative "routine/backup_first"
require_relative "routine/printing"
require_relative "routine/store_locking"
require_relative "routine/given_facts"
require_relative "routine/graph_report"
require_relative "workflow"
require_relative "workflows/registry"
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
    extend BackupFirst::Declaration
    extend Printing::Facts
    extend StoreLocking::Declaration
    extend GivenFacts
    include Preview
    include BackupFirst
    include Printing
    include StoreLocking
    include GraphReport

    KEPT_RUN_WORDS = "The run of the call is kept for a resume"

    class << self
      def workflow(key, **edge, &branches)
        chain.add(key, edge[:next], &branches)
      end

      def chain = (@chain ||= Chain.new(self))

      # The namespace that holds the chain's workflows and their REGISTRY.
      def workflows = Workflows

      # Every name a step may read or write: the tool's arguments and options,
      # the facts each workflow in the chain declares and the facts the tool gives.
      def declared_facts = declared_names + chain.facts + given_facts.keys

      # Runs once per process, on the first call, and raises every problem at
      # once, so a reordered chain never skips a workflow in silence.
      def verify
        @verified ||= begin
          problems = chain_problems
          raise Invalid, "#{name}: #{problems.join("; ")}" if problems.any?

          true
        end
      end

      def chain_problems = chain.problems(declared_names + given_facts.keys) + preview_problems
    end

    def call
      self.class.verify
      back_up_first
      previewing? ? preview : run_chain
    end

    private

    def finish(command_run)
      ctx = context(command_run)
      report(ctx) do
        under_store_lock do
          refuse_hand_edits(ctx)
          walk(command_run, ctx)
        end
      end
    end

    # A resumed command run brings back what its workflows found; this call's
    # arguments and options always win, nil included.
    def context(command_run)
      klass = self.class
      Context.new(declared: klass.declared_facts, facts: command_run.facts.merge(klass.given_facts, parsed, preview_facts), graphs: routine_graphs, harness: Context::Harness.of(environment, scope, settings), clock: environment.clock)
    end

    def chain = self.class.chain

    # The printed lines and rows go first on every end, failure included, so a gate
    # that says "see above" has something above it. Then the call says what
    # it wrote: the rows, one phrase per database, and the files it
    # printed. The end value prints its own last lines and gives the exit code;
    # an error that stopped the call is raised after the lines above it.
    #
    #   wrote: 1 intent and 1 ledger line in work_graph.db
    def report(ctx)
      value = nil
      value = yield
    ensure
      ctx.print_to(output)
      report_graphs if touches_graphs?
      @exit_code = value.report(output) if value
    end

    # The open command run for this tool and subject, or a new one.
    def open_command_run
      found = graphs.retrieval.command_run(words, subject) if keeps_command_run?
      found&.open? ? found : CommandRun.fresh(words, subject, environment.now)
    end

    # The subject arguments of this call, joined, or nil when none is set.
    def subject
      parts = Array(self.class.subject).filter_map { |name| parsed[name] }
      parts.join("-") unless parts.empty?
    end

    def save_command_run(command_run)
      graphs.work.save_command_run(command_run) if keeps_command_run?
    end

    # A command that writes keeps its command run, so a resumed write finds
    # its facts. A read, and a dry run, keep none.
    def keeps_command_run? = self.class.writes.any? && !self.class.keeps_no_command_run? && !parsed[:dry_run]
  end
end
