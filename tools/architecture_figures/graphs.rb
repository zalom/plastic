# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Graphs
    META = Diagram::Meta.new(file: "graphs.svg", width: 1160, height: 640, title: "The three graphs and their databases",
      desc: "Graph::WorkGraph writes the rows of every graph and Graph::RetrievalGraph reads them. The work graph lives in work_graph.db. The knowledge graph and the retrieval graph both live in knowledge_graph.db. Graph::Printer prints the rows as files in the store folder.")
    BOXES = Diagram.parse(<<~TABLE).freeze
      writer | | 30 20 1110 | Graph::WorkGraph | class | line | mono | The write side: it writes the rows of every graph.
      work | | 30 160 330 | Work graph | graph | agent | | What is being built: intents, with / their nodes and the edges between.
      knowledge | | 490 160 330 | Knowledge graph | graph | owner | | What is known: documents, / rulings and the links between.
      retrieval | | 850 160 290 | Retrieval graph | graph | end | | What is found: the search index / over the documents.
      work_db | cylinder | 30 300 330 | work_graph.db | | | | intents, nodes, edges
      knowledge_db | cylinder | 490 300 650 | knowledge_graph.db | | | | documents, rulings, links, document_heads
      reader | | 30 420 1110 | Graph::RetrievalGraph | class | line | mono | The read side: it reads the rows of every graph and writes nothing.
      printer | | 30 540 330 | Graph::Printer | class | line | mono | Prints the rows as files.
      files | | 490 540 650 | Files in the store folder | | line | | spec.md, graph.json, savepoint.md, outcome.md
    TABLE
    ARROWS = [
      ["writer.bottom@0.15", "work.top", ["writes"]],
      ["writer.bottom@0.56818", "knowledge.top", ["writes"]],
      ["writer.bottom@0.87727", "retrieval.top", ["writes"]],
      ["work.bottom", "work_db.top", ["rows"]],
      ["knowledge.bottom", "knowledge_db.top@0.25385", ["rows"]],
      ["retrieval.bottom", "knowledge_db.top@0.77692", ["rows"]],
      ["reader.top@0.15", "work_db.bottom", ["reads"]],
      ["reader.top@0.5", "knowledge_db.bottom@0.5", ["reads"]],
      ["printer.right", "files.left", ["prints"]]
    ].freeze
    NAMES = [
      *%w[Graph::WorkGraph Graph::RetrievalGraph Graph::Printer].map { |name| ["class", name, name] },
      *%w[work_graph.db knowledge_graph.db].map { |name| ["database", name, name] },
      *%w[intents nodes edges documents rulings links document_heads].map { |name| ["table", name, name] }
    ].freeze

    def self.diagrams = [Diagram.new(META, BOXES, ARROWS)]

    def self.files = Diagram.merge(diagrams)

    def self.names = NAMES
  end
end
