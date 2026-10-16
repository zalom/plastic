# frozen_string_literal: true

module CommandReference
  # The page that explains the command DSL: real kernel code beside what it declares.
  class DslPage
    FILES = {
      routine: "lib/plastic/routine.rb", declarations: "lib/plastic/cli/declarations.rb",
      chain: "lib/plastic/routine/chain.rb", edge: "lib/plastic/routine/edge.rb",
      link: "lib/plastic/routine/link.rb", branches: "lib/plastic/routine/branches.rb",
      workflow: "lib/plastic/workflow.rb", code: "lib/plastic/code_workflow.rb",
      agent: "lib/plastic/agent_workflow.rb", finished: "lib/plastic/finished.rb",
      command: "lib/plastic/cli/command.rb"
    }.freeze
    EXAMPLE = "intent end"
    END_FILES = { "Finished" => "finished", "HandedOff" => "handed_off", "Failed" => "failed", "Refused" => "refused" }.freeze

    attr_reader :source

    def initialize(model, root)
      @model = model
      @root = root
      @source = Source.new(root)
    end

    def page = @page ||= @model.page(EXAMPLE)

    def examples = ["#{EXAMPLE} #{page.arguments.map(&:label).join(" ")}".strip]

    def code_flow = @code_flow ||= Plastic::Workflow.fetch(:code_revise_intent)

    def agent_flow = @agent_flow ||= Plastic::Workflow.fetch(:agent_check_merge)

    def line(key, pattern) = @source.find_line(FILES.fetch(key), pattern)

    def flow_file(flow) = @source.relative(Object.const_source_location(flow.name).first)

    def flow_line(flow) = @source.find_line(flow_file(flow), /^\s*class #{Words.short(flow)}\b/)

    def ends
      @ends ||= @source.lines("lib/plastic/finished.rb").filter_map { |text| text.match(/^\s*#\s+(\w+)\s+exit (\d)\s+(.*)$/) }.map do |found|
        name, code, words = found.captures
        path = "lib/plastic/#{END_FILES.fetch(name)}.rb"
        { name:, exit_code: code, words:, file: path, line: @source.find_line(path, /^\s*#{name} = /) }
      end
    end

    def drawings = figures.transform_values { |drawing| drawing.canvas.standalone }

    private

    def figures
      home = page
      { "declare-command.svg" => Dsl::DeclareCommand.new(home, class_rows(home.file, "End")), **workflow_figures,
        "endings.svg" => Dsl::EndValues.new(ends), "chain.svg" => Figures::Chain.new(home) }
    end

    def workflow_figures
      { "code-workflow.svg" => flow_figure(Dsl::CodeFlow, code_flow), "agent-workflow.svg" => flow_figure(Dsl::AgentFlow, agent_flow) }
    end

    def flow_figure(type, flow) = type.new(Words.short(flow), statements(flow))

    def class_rows(file, name) = Dsl::ClassRows.new(@source.lines(file), name).rows

    def statements(flow) = Dsl::Statements.new(class_rows(flow_file(flow), Words.short(flow))).rows
  end
end
