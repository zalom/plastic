# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Containers
    META = Diagram::Meta.new(file: "containers.svg", width: 1160, height: 600, title: "What runs and where Plastic keeps its data",
      desc: "The plastic program reads and writes four SQLite databases: local.db in the home, and work_graph.db, knowledge_graph.db and references.db in each store. Files are printed from the rows into the store folder, and a sync up reads hand edits back. Backups are copies of a store's databases.")
    BOXES = Diagram.parse(<<~TABLE).freeze
      home | zone | 10 10 1140 170 | Plastic home | | | |
      instructions | | 30 44 230 | PLASTIC.md | file | agent | | The always-on instructions / the harness imports.
      program | | 290 44 250 | bin/plastic | program | code | mono | Ruby. One command, plastic, / and the three hooks.
      local | cylinder | 580 50 240 | local.db | | | | routine_runs, sessions, / locks, backups
      registry | | 860 44 270 | config.yml, projects.yml | files | line | | Settings, and the list of / projects: slug to repository.
      store | zone | 10 215 1140 375 | A store: one for each project, under stores/ | | | |
      work | cylinder | 40 250 250 | work_graph.db | | | | intents, nodes, edges
      knowledge | cylinder | 320 250 250 | knowledge_graph.db | | | | documents, rulings, links
      references | cylinder | 600 250 250 | references.db | | | | sqlar
      backups | | 880 244 250 | backups/ | folder | line | | Copies of the three databases, / one folder for each backup.
      index | | 40 430 250 | store/index.json | file | line | mono | Every intent, in order.
      folder | | 320 430 530 | ID--slug/ | intent folder | line | | spec.md, graph.json, savepoint.md, / outcome.md and context.json, printed from the rows.
    TABLE
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
