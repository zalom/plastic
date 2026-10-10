# frozen_string_literal: true

module CommandReference
  # Where a workflow lives: its class, and the parents and modules that hold its steps.
  class WorkflowHomes
    MODULES = "Plastic::Workflows::"

    attr_reader :source, :workflow

    def self.holding(mod, value) = mod.constants.select { |name| mod.const_get(name) == value }

    def initialize(source, workflow)
      @source = source
      @workflow = workflow
    end

    def declared = @declared ||= Object.const_source_location(@workflow.name)

    def files = @files ||= [@source.relative(declared.first), *[*parents, *modules].map { |mod| module_file(mod) }].uniq

    def holders(value) = modules.flat_map { |mod| WorkflowHomes.holding(mod, value) }

    private

    def parents = @workflow.ancestors.drop(1).take_while { |mod| mod.superclass != Plastic::Workflow }.grep(Class)

    def modules = @workflow.singleton_class.included_modules.select { |mod| mod.name.to_s.start_with?(MODULES) }

    def module_file(mod) = @source.relative(Object.const_source_location(mod.name).first)
  end

  # One workflow read from the kernel: where it lives and what it declares, in the order it runs.
  class WorkflowReading
    CODE_WORKFLOW = "scripts/lib/plastic/code_workflow.rb"
    DEFAULT_OUTCOME = /A workflow with no outcome line has one outcome/

    def initialize(source, chain, key)
      @homes = WorkflowHomes.new(source, chain.fetch(key))
      @chain = chain
      @key = key
      @locator = Locator.new(source)
    end

    def source = @homes.source

    def workflow = @homes.workflow

    def flow = Flow.new(**identity, rows: workflow.steps.map { |step| row(step) }, outcomes:)

    def search(pattern) = @locator.search(files, pattern)

    def at(callable, word) = @locator.at(callable, word)

    def named(word, name) = @locator.named(files, word, name)

    def first(word) = @locator.first(files, word)

    def holders(value) = @homes.holders(value)

    def next_key(name) = @chain.next_key(@key, name)

    private

    def identity
      klass = workflow
      { key: @key, klass:, lane: klass.lane, file: files.first, line: @homes.declared.last, comment: source.class_comment(klass), facts: klass.facts }
    end

    def files = @homes.files

    def row(step) = StepReadings.reader(step).new(step, self).row

    def outcomes
      return [default_outcome] if workflow.outcomes.empty? && workflow.lane == "code"

      workflow.outcome_names.map { |name| OutcomeReading.new(name, self).outcome }
    end

    def default_outcome
      Outcome.new(:done, nil, true, nil, nil, next_key(:done), 0, CODE_WORKFLOW, source.find_line(CODE_WORKFLOW, DEFAULT_OUTCOME))
    end
  end
end
