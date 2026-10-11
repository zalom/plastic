# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module CommandCall
    META = Diagram::Meta.new(file: "command-call.svg", width: 1160, height: 580, title: "One command from call to report",
      desc: "The call plastic intent new runs through 10 steps. bin/plastic hands the words to CLI, which finds the row in CLI::TABLE. A Routine opens the Graph and runs the chain through Routine::Traversal. Workflows::WriteIntent writes the rows, Graph::Printer prints the files, and the report ends with exit code 0.")
    STEPS = [
      ["bin/plastic", "Runs CLI with the words", "of the call."],
      ["CLI", "Finds the row for intent new", "in CLI::TABLE."],
      ["Commands::IntentNew", "Loaded on demand; its", "options are read."],
      ["Routine", "Opens the Graph and", "starts a RoutineRun."],
      ["Routine::Traversal", "Runs the chain through", "Workflows::REGISTRY."],
      ["Workflows::WriteIntent", "Checks the call, then", "writes the rows."],
      ["Graph::Printer", "Prints the files of", "the intent folder."],
      ["Routine", "Saves the RoutineRun", "and builds the report."],
      ["CLI", "Prints the report."],
      ["bin/plastic", "Exits with code 0:", "the value is Finished."]
    ].freeze
    REPORT = ["intent: ID", "wrote: 1 routine run in local.db", "1 intent and 1 savepoint line in work_graph.db", "1 document and 1 document head in knowledge_graph.db",
      "files: store/index.json", "store/ID--slug/intent.md", "store/ID--slug/savepoint.md", "store/ID--slug/graph.json", "next: plastic next", "because: intent ID has its rows and its files"].freeze
    NAMES = [["path", "bin/plastic", "bin/plastic"], ["command", "intent new", "intent new"], *%w[CLI CLI::TABLE Commands::IntentNew Routine RoutineRun Routine::Traversal Workflows::REGISTRY Workflows::WriteIntent Graph::Printer Finished].map { |name| ["class", name, name] }].freeze

    SPOTS = [[0, 20], [1, 20], [2, 20], [3, 20], [4, 20], [4, 170], [3, 170], [2, 170], [1, 170], [0, 170]].freeze

    def self.boxes
      STEPS.zip(SPOTS).each_with_index.to_h do |((name, *lines), (column, row)), at|
        [:"step#{at}", { left: 15 + (column * 227), top: row, width: 207, name: name, mono: true, kind: "Step #{at + 1}", tone: :code, lines: lines }]
      end
    end

    def self.arrows
      sides = [%w[right left]] * 4 + [%w[bottom top]] + [%w[left right]] * 4
      sides.each_with_index.map { |(out, into), at| ["step#{at}.#{out}", "step#{at + 1}.#{into}"] }
    end

    def self.diagrams = [Diagram.new(META, boxes, arrows, [Shapes::Label.new(left: 15, top: 340, text: "What the call prints", style: "t"), Shapes::Terminal.new(left: 15, top: 352, width: 1130, lines: REPORT)])]

    def self.files = Diagram.merge(diagrams)

    def self.names = NAMES
  end
end
