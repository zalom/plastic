# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Graphs
    META = Diagram::Meta.new(file: "graphs.svg", width: 1160, height: 480, title: "The three graphs and their databases",
      desc: "The work graph lives in work_graph.db. The knowledge graph and the retrieval graph both live in knowledge_graph.db. Graph::WorkGraph and Graph::RetrievalGraph read and write the rows, and Graph::Printer prints them as files.")
    BOXES = Diagram.parse(<<~TABLE).freeze
      work_class | | 30 20 330 | Graph::WorkGraph | class | code | mono | Opens the work graph.
      retrieval_class | | 490 20 330 | Graph::RetrievalGraph | class | code | mono | Opens the knowledge and / retrieval graphs.
      work | | 30 170 330 | Work graph | graph | agent | | What is being built: intents, with / their nodes and the edges between.
      knowledge | | 490 170 330 | Knowledge graph | graph | owner | | What is known: documents, / rulings and the links between.
      retrieval | | 850 170 290 | Retrieval graph | graph | end | | What is found: the search index / over the documents.
      work_db | cylinder | 30 300 330 | work_graph.db | | | | intents, nodes, edges
      knowledge_db | cylinder | 490 300 650 | knowledge_graph.db | | | | documents, rulings, links, document_heads
      printer | | 30 400 330 | Graph::Printer | | line | mono |
      files | | 490 396 650 | Files in the store folder | | line | | spec.md, graph.json, savepoint.md, outcome.md
    TABLE
    ARROWS = [
      ["work_class.bottom", "work.top", ["opens"]],
      ["retrieval_class.bottom@0.25", "knowledge.top@0.25", ["opens"]],
      ["retrieval_class.bottom@0.75", "retrieval.top@0.25"],
      ["work.bottom", "work_db.top", ["rows"]],
      ["printer.right", "files.left", ["prints"]],
      ["knowledge.bottom", "knowledge_db.top@0.2", ["rows"]],
      ["retrieval.bottom", "knowledge_db.top@0.8", ["rows"]]
    ].freeze
    NAMES = [
      *%w[Graph::WorkGraph Graph::RetrievalGraph Graph::Printer].map { |name| ["class", name, name] },
      *%w[work_graph.db knowledge_graph.db].map { |name| ["database", name, name] },
      *%w[intents nodes edges documents rulings links document_heads].map { |name| ["table", name, name] }
    ].freeze

    def self.files = Diagram.new(META, BOXES, ARROWS).files

    def self.names = NAMES
  end
end
