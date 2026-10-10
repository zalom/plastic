# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Graphs
    META = Diagram::Meta.new(file: "graphs.svg", width: 1160, height: 480, title: "The three graphs and their databases",
      desc: "The work graph lives in work_graph.db. The knowledge graph and the retrieval graph both live in knowledge_graph.db. Graph::WorkGraph and Graph::RetrievalGraph read and write the rows, and Graph::Printer prints them as files.")
    BOXES = {
      work_class: { left: 30, top: 20, width: 330, name: "Graph::WorkGraph", mono: true, kind: "class", tone: :code, lines: ["Opens the work graph."] },
      retrieval_class: { left: 490, top: 20, width: 330, name: "Graph::RetrievalGraph", mono: true, kind: "class", tone: :code, lines: ["Opens the knowledge and", "retrieval graphs."] },
      work: { left: 30, top: 170, width: 330, name: "Work graph", kind: "graph", tone: :agent, lines: ["What is being built: intents, with", "their nodes and the edges between."] },
      knowledge: { left: 490, top: 170, width: 330, name: "Knowledge graph", kind: "graph", tone: :owner, lines: ["What is known: documents,", "rulings and the links between."] },
      retrieval: { left: 850, top: 170, width: 290, name: "Retrieval graph", kind: "graph", tone: :end, lines: ["What is found: the search index", "over the documents."] },
      work_db: { type: :cylinder, left: 30, top: 300, width: 330, name: "work_graph.db", lines: ["intents, nodes, edges"] },
      knowledge_db: { type: :cylinder, left: 490, top: 300, width: 650, name: "knowledge_graph.db", lines: ["documents, rulings, links, document_heads"] },
      printer: { left: 30, top: 400, width: 330, name: "Graph::Printer", mono: true, tone: :line },
      files: { left: 490, top: 396, width: 650, name: "Files in the store folder", tone: :line, lines: ["spec.md, graph.json, savepoint.md, outcome.md"] }
    }.freeze
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
