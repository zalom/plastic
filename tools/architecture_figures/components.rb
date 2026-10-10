# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Components
    META = Diagram::Meta.new(file: "components.svg", width: 1240, height: 640, title: "The components of the plastic kernel",
      desc: "The command line finds a command in CLI::TABLE and builds a Routine. The Routine opens the Graph, runs the workflow chain through Routine::Traversal and reports one of four end values. Commands, workflows and graphs are separate groups of classes.")
    BOXES = {
      dispatch: { type: :zone, left: 10, top: 10, width: 1220, height: 150, name: "Dispatch: one command in, one report out" },
      cli: { left: 30, top: 44, width: 270, name: "CLI", mono: true, kind: "class", tone: :code, lines: ["Reads the words, finds the row."] },
      table: { left: 330, top: 44, width: 270, name: "CLI::TABLE", mono: true, kind: "constant", tone: :line, lines: ["One row for each command."] },
      routine: { left: 630, top: 44, width: 270, name: "Routine", mono: true, kind: "class", tone: :code, lines: ["Runs one command to a report."] },
      hook: { left: 930, top: 44, width: 270, name: "Hook", mono: true, kind: "class", tone: :agent, lines: ["Answers the three hook events."] },
      commands: { type: :zone, left: 10, top: 190, width: 600, height: 190, name: "Commands" },
      declarations: { left: 30, top: 222, width: 270, name: "CLI::Declarations", mono: true, kind: "module", tone: :line, lines: ["Options a command declares."] },
      scope: { left: 330, top: 222, width: 260, name: "CLI::Scope", mono: true, kind: "class", tone: :line, lines: ["Which project and store."] },
      workflows: { type: :zone, left: 640, top: 190, width: 590, height: 190, name: "Workflows" },
      registry: { left: 660, top: 222, width: 270, name: "Workflows::REGISTRY", mono: true, kind: "constant", tone: :line, lines: ["Every workflow by name."] },
      traversal: { left: 950, top: 222, width: 260, name: "Routine::Traversal", mono: true, kind: "class", tone: :code, lines: ["Walks the chain of workflows."] },
      graphs: { type: :zone, left: 10, top: 410, width: 1220, height: 215, name: "Graphs" },
      graph: { left: 30, top: 444, width: 270, name: "Graph", mono: true, kind: "module", tone: :code, lines: ["Opens the databases."] },
      work: { left: 330, top: 444, width: 270, name: "Graph::WorkGraph", mono: true, kind: "class", tone: :line, lines: ["Intents, nodes and edges."] },
      retrieval: { left: 630, top: 444, width: 270, name: "Graph::RetrievalGraph", mono: true, kind: "class", tone: :line, lines: ["Documents, rulings, links."] },
      printer: { left: 930, top: 444, width: 270, name: "Graph::Printer", mono: true, kind: "class", tone: :line, lines: ["Prints the rows as files."] }
    }.freeze
    ARROWS = [
      ["cli.right", "table.left", ["finds"]],
      ["table.right", "routine.left", ["builds"]],
      ["routine.bottom@0.5", "traversal.top@0.3", ["runs"]],
      ["traversal.left", "registry.right", ["looks up"]],
      ["routine.bottom@0.2", "graph.top@0.5", ["opens"]]
    ].freeze
    NAMES = %w[CLI CLI::TABLE CLI::Declarations CLI::Scope Routine Routine::Traversal Hook Workflows::REGISTRY Graph Graph::WorkGraph Graph::RetrievalGraph Graph::Printer].map { |name| ["class", name, name] }.freeze

    def self.files = Diagram.new(META, BOXES, ARROWS).files

    def self.names = NAMES
  end
end
