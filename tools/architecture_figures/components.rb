# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Components
    META = Diagram::Meta.new(file: "components.svg", width: 1240, height: 955, title: "The components of the plastic kernel",
      desc: "The command line finds a row in CLI::TABLE and builds a Routine. The Routine runs the workflow chain through Routine::Traversal, which finds each workflow in Workflows::REGISTRY, and it opens the Graph. Graph::WorkGraph writes every database through Graph::Work::Writers, Graph::RetrievalGraph reads every database, and Graph::Printer prints files.")
    BOXES = Diagram.parse(<<~TABLE).freeze
      commands | zone | 10 10 1220 235 | Commands: one call in, one report out | | | |
      routine | | 30 44 260 | Routine | class | code | mono | Runs one command to a report.
      cli | | 390 44 230 | CLI | class | code | mono | Reads the words.
      table | | 720 44 230 | CLI::TABLE | constant | line | mono | One row for each command.
      declarations | | 390 150 230 | CLI::Declarations | module | line | mono | Options a command declares.
      scope | | 720 150 230 | CLI::Scope | class | line | mono | Which project and store.
      hook | | 1000 150 210 | Hook | class | agent | mono | Answers the hook events.
      workflows | zone | 190 285 840 240 | Workflows | | | |
      traversal | | 205 317 230 | Routine::Traversal | class | code | mono | Walks the chain of workflows.
      registry | | 495 317 230 | Workflows::REGISTRY | constant | line | mono | Every workflow by name.
      code | | 495 430 230 | CodeWorkflow | class | line | mono | Ruby steps, in order.
      agent | | 785 430 230 | AgentWorkflow | class | agent | mono | Steps in words for the agent.
      graph | zone | 10 565 1220 376 | Graph module | | | |
      work | | 30 601 770 | Graph::WorkGraph | class | line | mono | The write side of every database.
      writers | | 880 601 330 | Graph::Work::Writers | class | line | mono | Does the writes for the work graph.
      local | cylinder | 30 735 170 | local.db | | | |
      work_db | cylinder | 230 735 170 | work_graph.db | | | |
      knowledge_db | cylinder | 430 735 170 | knowledge_graph.db | | | |
      references_db | cylinder | 630 735 170 | references.db | | | |
      database | | 880 722 330 | Graph::Database | class | code | mono | One SQLite file, one transaction a write.
      retrieval | | 30 842 770 | Graph::RetrievalGraph | class | line | mono | The read side of every database. It writes nothing.
      printer | | 880 842 330 | Graph::Printer | class | line | mono | Prints the rows as files.
    TABLE
    ARROWS = [
      ["cli.right", "table.left", ["finds the row"]],
      ["cli.left", "routine.right", ["builds"]],
      ["routine.bottom@0.9423", "traversal.top@0.3043", ["runs"]],
      ["traversal.right", "registry.left", ["looks up"]],
      ["registry.bottom", "code.top", ["holds"]],
      ["registry.right", "agent.top", ["holds"]],
      ["routine.bottom@0.27", "graph.top@0.0739", ["opens"]],
      ["work.bottom@0.11039", "local.top", ["writes"]],
      ["work.bottom@0.37013", "work_db.top", ["writes"]],
      ["work.bottom@0.62987", "knowledge_db.top", ["writes"]],
      ["work.bottom@0.88961", "references_db.top", ["writes"]],
      ["retrieval.top@0.11039", "local.bottom", ["reads"]],
      ["retrieval.top@0.37013", "work_db.bottom", ["reads"]],
      ["retrieval.top@0.62987", "knowledge_db.bottom", ["reads"]],
      ["retrieval.top@0.88961", "references_db.bottom", ["reads"]],
      ["work.right", "writers.left", ["delegates"]],
      ["writers.bottom", "database.top", ["uses"]],
      ["retrieval.right", "database.left", ["uses"]]
    ].freeze
    NAMES = [
      *%w[CLI CLI::TABLE CLI::Declarations CLI::Scope Routine Routine::Traversal Hook Workflows::REGISTRY CodeWorkflow AgentWorkflow
        Graph Graph::WorkGraph Graph::Work::Writers Graph::Database Graph::RetrievalGraph Graph::Printer].map { |name| ["class", name, name] },
      *%w[local.db work_graph.db knowledge_graph.db references.db].map { |name| ["database", name, name] }
    ].freeze

    def self.diagrams = [Diagram.new(META, BOXES, ARROWS)]

    def self.files = Diagram.merge(diagrams)

    def self.names = NAMES
  end
end
