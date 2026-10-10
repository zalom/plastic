# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Containers
    META = Diagram::Meta.new(file: "containers.svg", width: 1160, height: 600, title: "What runs and where Plastic keeps its data",
      desc: "The plastic program reads and writes four SQLite databases: local.db in the home, and work_graph.db, knowledge_graph.db and references.db in each store. Files are printed from the rows into the store folder, and a sync up reads hand edits back. Backups are copies of a store's databases.")
    BOXES = {
      home: { type: :zone, left: 10, top: 10, width: 1140, height: 170, name: "Plastic home" },
      instructions: { left: 30, top: 44, width: 230, name: "PLASTIC.md", kind: "file", tone: :agent, lines: ["The always-on instructions", "the harness imports."] },
      program: { left: 290, top: 44, width: 250, name: "bin/plastic", mono: true, kind: "program", tone: :code, lines: ["Ruby. One command, plastic,", "and the three hooks."] },
      local: { type: :cylinder, left: 580, top: 50, width: 240, name: "local.db", lines: ["routine_runs, sessions,", "locks, backups"] },
      registry: { left: 860, top: 44, width: 270, name: "config.yml, projects.yml", kind: "files", tone: :line, lines: ["Settings, and the list of", "projects: slug to repository."] },
      store: { type: :zone, left: 10, top: 215, width: 1140, height: 375, name: "A store: one for each project, under stores/" },
      work: { type: :cylinder, left: 40, top: 250, width: 250, name: "work_graph.db", lines: ["intents, nodes, edges"] },
      knowledge: { type: :cylinder, left: 320, top: 250, width: 250, name: "knowledge_graph.db", lines: ["documents, rulings, links"] },
      references: { type: :cylinder, left: 600, top: 250, width: 250, name: "references.db", lines: ["sqlar"] },
      backups: { left: 880, top: 244, width: 250, name: "backups/", kind: "folder", tone: :line, lines: ["Copies of the three databases,", "one folder for each backup."] },
      index: { left: 40, top: 430, width: 250, name: "store/index.json", mono: true, kind: "file", tone: :line, lines: ["Every intent, in order."] },
      folder: { left: 320, top: 430, width: 530, name: "ID--slug/", kind: "intent folder", tone: :line, lines: ["spec.md, graph.json, savepoint.md,", "outcome.md and context.json, printed from the rows."] }
    }.freeze
    ARROWS = [
      ["program.right", "local.left", ["rows"]],
      ["program.bottom@0.2", "work.top", ["reads and writes rows"]],
      ["program.bottom@0.5", "knowledge.top"],
      ["program.bottom@0.8", "references.top"],
      ["work.bottom", "index.top", ["printed"]],
      ["knowledge.bottom", "folder.top@0.2", ["printed from the rows;", "sync up reads edits back"]]
    ].freeze
    NAMES = [
      ["path", "bin/plastic", "bin/plastic"],
      *%w[local.db work_graph.db knowledge_graph.db references.db].map { |name| ["database", name, name] },
      *%w[routine_runs sessions locks backups intents nodes edges documents rulings links sqlar].map { |name| ["table", name, name] },
      *%w[store/index.json spec.md graph.json savepoint.md outcome.md context.json].map { |name| ["store_file", name, name] },
      ["command", "sync up", "sync up"]
    ].freeze

    def self.files = Diagram.new(META, BOXES, ARROWS).files

    def self.names = NAMES
  end
end
