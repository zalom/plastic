# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Components
    META = Diagram::Meta.new(file: "components.svg", width: 1240, height: 640, title: "The components of the plastic kernel",
      desc: "The command line finds a command in CLI::TABLE and builds a Routine. The Routine opens the Graph, runs the workflow chain through Routine::Traversal and reports one of four end values. Commands, workflows and graphs are separate groups of classes.")
    BOXES = Diagram.parse(<<~TABLE).freeze
      dispatch | zone | 10 10 1220 150 | Dispatch: one command in, one report out | | | |
      cli | | 30 44 270 | CLI | class | code | mono | Reads the words, finds the row.
      table | | 330 44 270 | CLI::TABLE | constant | line | mono | One row for each command.
      routine | | 630 44 270 | Routine | class | code | mono | Runs one command to a report.
      hook | | 930 44 270 | Hook | class | agent | mono | Answers the three hook events.
      commands | zone | 10 190 600 190 | Commands | | | |
      declarations | | 30 222 270 | CLI::Declarations | module | line | mono | Options a command declares.
      scope | | 330 222 260 | CLI::Scope | class | line | mono | Which project and store.
      workflows | zone | 640 190 590 190 | Workflows | | | |
      registry | | 660 222 270 | Workflows::REGISTRY | constant | line | mono | Every workflow by name.
      traversal | | 950 222 260 | Routine::Traversal | class | code | mono | Walks the chain of workflows.
      graphs | zone | 10 410 1220 215 | Graphs | | | |
      graph | | 30 444 270 | Graph | module | code | mono | Opens the databases.
      work | | 330 444 270 | Graph::WorkGraph | class | line | mono | Intents, nodes and edges.
      retrieval | | 630 444 270 | Graph::RetrievalGraph | class | line | mono | Documents, rulings, links.
      printer | | 930 444 270 | Graph::Printer | class | line | mono | Prints the rows as files.
    TABLE
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
