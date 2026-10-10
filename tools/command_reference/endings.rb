# frozen_string_literal: true

module CommandReference
  # Lists every way one command can end, each with the line that decides it.
  class Endings
    NONE = "prints no next: line"
    RUNTIME = "decided at run time"
    CODE_WORKFLOW = "scripts/lib/plastic/code_workflow.rb"
    RAISES = { "Usage" => 2, "Refusal" => 3, "Failure" => 1 }.freeze
    RAISE_LINE = /\braise (?:CLI::)?(?:Command::)?(Usage|Refusal|Failure)\b/
    NEXT_LINE = /\bnext_step\((?:"([^"]+)"|[^,)]+)/

    def initialize(source)
      @source = source
    end

    def call(kind, files, flows, own_call)
      [*flows.flat_map { |flow| flow_endings(flow) }, *rescued(flows), *((kind == :hook) ? [] : file_endings(files)), *hook_endings(kind, files, own_call)]
    end

    private

    def flow_endings(flow)
      gates(flow) + flow.outcomes.filter_map { |outcome| closing(flow, outcome) }
    end

    def gates(flow)
      flow.klass.steps.zip(flow.rows).filter_map do |step, row|
        next unless step.is_a?(Plastic::CodeWorkflow::Gate)

        Ending.new(:gate, (step.stops == :refusal) ? 3 : 1, step.offers || NONE, row.name, row.file, row.line)
      end
    end

    def closing(flow, outcome)
      return unless outcome.to == :noop

      kind = (flow.lane == "agent" && outcome.name == :handoff) ? :handoff : :outcome
      Ending.new(kind, outcome.exit_code, outcome.offers || NONE, outcome.because, outcome.file, outcome.line)
    end

    def rescued(flows)
      return [] unless flows.any? { |flow| flow.lane == "code" && flow.klass.steps.any? { |step| !step.is_a?(Plastic::CodeWorkflow::Gate) } }

      [Ending.new(:rescue, 1, NONE, "a step raises", CODE_WORKFLOW, @source.find_line(CODE_WORKFLOW, /^\s*rescue => error/))]
    end

    def file_endings(files)
      files.flat_map { |file| raises(file) + next_steps(file) }
    end

    def raises(file)
      @source.lines(file).each_with_index.filter_map do |text, index|
        code = RAISES[text[RAISE_LINE, 1]]
        Ending.new(:raise, code, NONE, text.strip, file, index + 1) if code
      end
    end

    def next_steps(file)
      @source.lines(file).each_with_index.filter_map do |text, index|
        match = text.match(NEXT_LINE) or next
        Ending.new(:next_step, 0, match[1] || RUNTIME, text.strip, file, index + 1)
      end
    end

    def hook_endings(kind, files, own_call)
      return [] unless kind == :hook

      [Ending.new(:respond, 0, NONE, "answers the event", own_call.file, own_call.line), *files.flat_map { |file| decisions(file) }]
    end

    def decisions(file)
      @source.lines(file).each_with_index.filter_map do |text, index|
        Ending.new(:decision, 0, NONE, "blocks the stop", file, index + 1) if text.include?('"decision"')
      end
    end
  end
end
