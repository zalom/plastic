# frozen_string_literal: true

require_relative "../diagram"
require_relative "../matrix"

module ArchitectureFigures
  module Delivery
    # What each step does to the three graphs, as a table. See docs/contributing/ARCHITECTURE.md.
    module Table
      META = Diagram::Meta.new(file: "delivery-graphs.svg", width: 1160, height: 770, title: "What each delivery step does to the three graphs",
        desc: "For each step of delivery, the rows the knowledge graph, the retrieval graph and the work graph receive, give or print as files.")
      ROWS = [
        { title: "1  Start", commands: ["intent new"], cells: [[[:writes, "the intent document"]], [], [[:writes, "the intent row"], [:prints, "the folder, store/index.json"]]] },
        { title: "2  Context", commands: ["intent discover", "intent context"], cells: [[[:reads, "documents, rulings, links"]], [[:writes, "discoveries and context"], [:prints, "context.json"]], []] },
        { title: "3  Grilling", commands: ["intent spec", "intent rule"], cells: [[[:writes, "a ruling for each decision"]], [[:reads, "the intent's context"]], []] },
        { title: "4  One spec", commands: ["spec.md"], cells: [[[:writes, "done criteria with keys"]], [], []] },
        { title: "5  You say deliver", commands: ["intent approve"], cells: [[], [], [[:writes, "the go-ahead row"]]] },
        { title: "6  Plan the graph", commands: ["node add", "edge add"], cells: [[[:reads, "the done criteria keys"]], [[:reads, "the intent's context"]], [[:writes, "nodes and edges"], [:prints, "graph.json, the checklist"]]] },
        { title: "7  Work the nodes", commands: ["node claim", "node done"], cells: [[[:reads, "the spec and its rulings"]], [[:reads, "the node's context"]], [[:writes, "claims, retries, findings"], [:prints, "graph.json"]]] },
        { title: "8  Judge", commands: ["intent judge"], cells: [[[:reads, "spec, rulings, outcome.md"]], [], [[:writes, "the verdict"], [:prints, "graph.json"]]] },
        { title: "9  Review", commands: ["outcome.md"], cells: [[[:writes, "the pull request and approval"]], [], []] },
        { title: "10  Close", commands: ["intent end"], cells: [[[:reads, "outcome.md"]], [], [[:reads, "the verdict and every node"], [:writes, "status done, lock released"], [:prints, "store/index.json"]]] },
        { title: "Any time", commands: ["intent abandon"], dashed: true, cells: [[[:writes, "a supersedes link, if any"]], [], [[:writes, "status abandoned"], [:prints, "store/index.json"]]] }
      ].freeze
      TABLE = Shapes::Matrix.new(left: 30, top: 10, columns: [290, 560, 830], heads: ["Step and its commands", "Knowledge graph", "Retrieval graph", "Work graph"], rows: ROWS)
      KEY = [Shapes::Mark.new(left: 30, top: 740, verb: :writes, text: "writes rows"), Shapes::Mark.new(left: 210, top: 740, verb: :reads, text: "reads rows"), Shapes::Mark.new(left: 390, top: 740, verb: :prints, text: "prints a file")].freeze

      def self.files = Diagram.new(META, {}, [], [TABLE, *KEY]).files

      def self.names = [*%w[intent\ context edge\ add node\ done].map { |name| ["command", name, name] }, *%w[spec.md outcome.md graph.json context.json].map { |name| ["store_file", name, name] }]
    end
  end
end
