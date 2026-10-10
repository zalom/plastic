# frozen_string_literal: true

require_relative "../diagram"

module ArchitectureFigures
  module Delivery
    # What each step does to the three graphs, as a table. See docs/contributing/ARCHITECTURE.md.
    module Table
      META = Diagram::Meta.new(file: "delivery-graphs.svg", width: 1160, height: 770, title: "What each delivery step does to the three graphs",
        desc: "For each step of delivery, the rows the knowledge graph, the retrieval graph and the work graph receive, give or print as files.")
      def self.row(line)
        title, commands, dashed, cells = line.strip.split(" | ", 4)
        { title: title, commands: commands.split(", "), dashed: (true if dashed == "dashed"), cells: cells.split(" || ").map { |cell| items(cell) } }.compact
      end

      def self.items(cell) = (cell == "-") ? [] : cell.split(" ; ").map { |item| mark(item) }

      def self.mark(item) = item.split(": ", 2).then { |verb, text| [verb.to_sym, text] }

      TEXT = <<~STEPS
        1  Start | intent new | - | writes: the intent document || - || writes: the intent row ; prints: the folder, store/index.json
        2  Context | intent discover, intent context | - | reads: documents, rulings, links || writes: discoveries and context ; prints: context.json || -
        3  Grilling | intent spec | - | reads: rulings and the spec || reads: the intent's context || -
        4  One spec | intent rule, intent revise | - | writes: rulings and a revision || - || -
        5  You say deliver | intent approve | - | - || - || writes: the go-ahead row
        6  Plan the graph | node add, edge add | - | reads: the done criteria keys || reads: the intent's context || writes: nodes and edges ; prints: graph.json, the checklist
        7  Work the nodes | node claim, node done | - | reads: the spec and its rulings || reads: the node's context || writes: claims, retries, findings ; prints: graph.json
        8  Judge | intent judge | - | reads: spec, rulings, outcome.md || - || writes: the verdict ; prints: graph.json
        9  Review | outcome.md | - | writes: the pull request and approval || - || -
        10  Close | intent end | - | reads: outcome.md || - || reads: the verdict and every node ; writes: status done, the completion row ; prints: store/index.json
        Any time | intent abandon | dashed | reads: a supersedes link, if any || - || writes: status abandoned ; prints: store/index.json
      STEPS
      ROWS = TEXT.lines.map { |line| row(line) }.freeze
      TABLE = Shapes::Matrix.new(left: 30, top: 10, columns: [290, 560, 830], heads: ["Step and its commands", "Knowledge graph", "Retrieval graph", "Work graph"], rows: ROWS)
      KEY = [Shapes::Mark.new(left: 30, top: 740, verb: :writes, text: "writes rows"), Shapes::Mark.new(left: 210, top: 740, verb: :reads, text: "reads rows"), Shapes::Mark.new(left: 390, top: 740, verb: :prints, text: "prints a file")].freeze

      def self.diagrams = [Diagram.new(META, {}, [], [TABLE, *KEY])]

      def self.files = Diagram.merge(diagrams)

      def self.names = [*%w[intent\ context intent\ revise edge\ add node\ done].map { |name| ["command", name, name] }, *%w[outcome.md graph.json context.json].map { |name| ["store_file", name, name] }]
    end
  end
end
