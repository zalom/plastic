# frozen_string_literal: true

module CommandReference
  # Reads one workflow of a chain: its rows and its outcomes, each with the line that declares it.
  class FlowReader
    FORGET = "forget a stop of an earlier call"
    CODE_WORKFLOW = "scripts/lib/plastic/code_workflow.rb"
    DEFAULT_OUTCOME = /A workflow with no outcome line has one outcome/

    def initialize(source, chain)
      @source = source
      @chain = chain
      @locator = Locator.new(source)
    end

    def call(key)
      workflow = @chain.fetch(key)
      file, line = Object.const_source_location(workflow.name)
      files = homes(workflow, @source.relative(file))
      Flow.new(key:, klass: workflow, lane: workflow.lane, file: files.first, line:, comment: @source.class_comment(workflow),
        facts: workflow.facts, rows: workflow.steps.map { |step| row(step, workflow, files) }, outcomes: outcomes(key, workflow, files))
    end

    private

    def homes(workflow, file)
      found = [*parents(workflow), *modules(workflow)].filter_map { |mod| module_file(mod) }
      [file, *found].uniq
    end

    def parents(workflow)
      workflow.ancestors.drop(1).take_while { |mod| mod != Plastic::CodeWorkflow && mod != Plastic::AgentWorkflow }.select { |mod| mod.is_a?(Class) }
    end

    def modules(workflow) = workflow.singleton_class.included_modules.select { |mod| mod.name&.start_with?("Plastic::Workflows::") }

    def module_file(mod)
      found = Object.const_source_location(mod.name)&.first
      @source.relative(found) if found
    end

    def row(step, workflow, files)
      case step
      when Plastic::CodeWorkflow::Gate then gate_row(step, workflow, files)
      when Plastic::CodeWorkflow::Read then read_row(step, files)
      when Plastic::CodeWorkflow::Step then step_row(step, files)
      else agent_row(step, files)
      end
    end

    def gate_row(gate, workflow, files)
      file, line = gate_place(gate, workflow, files)
      Row.new(:gate, gate.reason, @source.lambda_code(gate.pass), gate.stops, nil, file, line)
    end

    def gate_place(gate, workflow, files)
      @locator.at(gate.pass, "gate") || method_gate(gate, files) || reason_gate(gate, workflow, files) || @locator.first(files, "gate")
    end

    def method_gate(gate, files)
      return unless gate.pass.is_a?(Method)

      files.each { |file| (line = @source.find_line(file, /^\s*gate\b.*method\(:#{gate.pass.name}\)/)) and return [file, line] }
      nil
    end

    def reason_gate(gate, workflow, files)
      names = modules(workflow).flat_map { |mod| mod.constants.select { |name| mod.const_get(name) == gate.reason } }
      pattern = /^\s*gate\b.*(?:#{[Regexp.escape(gate.reason.inspect), *names.map { |name| "\\b#{name}\\b" }].join("|")})/
      files.each { |file| (line = @source.find_line(file, pattern)) and return [file, line] }
      nil
    end

    def read_row(read, files)
      file, line = forgotten(read) || @locator.at(read.body, "read") || @locator.named(files, "read", read.name)
      Row.new(:read, read.name, nil, nil, nil, file, line)
    end

    def forgotten(read)
      return unless read.name == FORGET

      [CODE_WORKFLOW, @source.find_line(CODE_WORKFLOW, /^\s*def forget_stop\b/)]
    end

    def step_row(step, files)
      file, line = @locator.at(step.body, "step") || @locator.named(files, "step", step.name)
      Row.new(:step, step.name, @source.lambda_code(step.done), :failure, nil, file, line)
    end

    def agent_row(step, files)
      file, line = @locator.named(files, "step", step.name)
      Row.new(:agent, step.name, @source.lambda_code(step.done), nil, step.say, file, line)
    end

    def outcomes(key, workflow, files)
      return [default_outcome(key)] if workflow.outcomes.empty? && workflow.lane == "code"

      workflow.outcome_names.map { |name| outcome(key, workflow, name, files) }
    end

    def default_outcome(key)
      Outcome.new(:done, nil, true, nil, nil, @chain.next_key(key, :done), 0, CODE_WORKFLOW, @source.find_line(CODE_WORKFLOW, DEFAULT_OUTCOME))
    end

    def outcome(key, workflow, name, files)
      line = workflow.outcomes.find { |found| found.name == name }
      handoff = workflow.lane == "agent" && name == :handoff
      file, number = outcome_place(line, name, files)
      Outcome.new(name, @source.lambda_code(line&.check), workflow.lane == "code" && (line.nil? || line.fallback?), line&.offers, line&.because,
        handoff ? :noop : @chain.next_key(key, name), handoff ? workflow.handoff_exit_code : 0, file, number)
    end

    def outcome_place(line, name, files)
      @locator.at(line&.check, "outcome") || @locator.named(files, "outcome", name) || @locator.first(files, "outcome")
    end
  end
end
