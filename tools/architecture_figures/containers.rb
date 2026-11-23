# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Containers
    META = Diagram::Meta.new(file: "containers.svg", width: 1160, height: 770, title: "What runs and where Plastic keeps its data",
      desc: "The install folder holds the active release, which is the plastic program. The Plastic home holds an exe/plastic launcher, and plastic.db. The program reads and writes four SQLite databases: plastic.db in the home, and work_graph.db, knowledge_graph.db and retrieval_graph.db in each store. Files are printed from the rows into the store folder, and a sync up reads hand edits back. Backups are copies of a store's databases.")
    BOXES = Diagram.parse(<<~TABLE).freeze
      install | zone | 10 10 1140 135 | Plastic install: ~/.local/share/plastic | | | |
      launcher | | 30 44 230 | ~/.local/bin/plastic | link | line | | Found on the PATH, / where you run plastic.
      active | | 330 44 260 | active/bin/plastic | program | code | | Ruby. One command, plastic, / and the three hooks.
      releases | | 660 44 220 | releases/VERSION/ | folder | line | | One folder for each release; / active points to one.
      download | | 940 44 190 | download/ | folder | line | | The files plastic update / fetched.
      home | zone | 10 165 1140 170 | Plastic home | | | |
      instructions | | 30 199 230 | PLASTIC.md | file | agent | | The always-on instructions / the harness imports.
      program | | 330 199 260 | exe/plastic | pointer | code | mono | A launcher that points to / the active program.
      local | cylinder | 640 205 210 | plastic.db | | | | command_runs, sessions, / settings
      registry | | 880 199 250 | config.yml, projects.yml | files | line | | Printed from the settings / rows, and the list of / projects: slug to repository.
      store | zone | 10 370 1140 390 | A store | | | |
      work | cylinder | 40 405 250 | work_graph.db | | | | intents, nodes, runs, edges
      knowledge | cylinder | 320 405 250 | knowledge_graph.db | | | | documents, rulings, links, sqlar
      retrieval | cylinder | 600 405 250 | retrieval_graph.db | | | | passages, search entries
      backups | | 880 399 250 | backups/ | folder | line | | Copies of the work and knowledge databases, / one folder for each backup.
      index | | 40 585 250 | store/index.json | file | line | mono | Every intent, in order.
      folder | | 600 585 530 | ID--slug/ | intent folder | line | | spec.md, graph.json, work.log, / outcome.md and context.json, printed from the rows.
    TABLE
    ARROWS = [
      ["launcher.right", "active.left", ["points to"], true],
      ["active.right", "releases.left", ["points to"], true],
      ["program.top", "active.bottom", ["points to"], true],
      ["program.right", "local.left", ["rows"]],
      ["program.bottom@0.2", "work.top", ["reads and writes rows"]],
      ["program.bottom@0.5", "knowledge.top"],
      ["program.bottom@0.8", "retrieval.top"],
      ["work.bottom", "index.top", ["printed"]],
      ["knowledge.bottom", "folder.top@0.2", ["printed from the rows;", "sync up reads edits back"]]
    ].freeze
    NAMES = [
      ["path", "exe/plastic", "exe/plastic"],
      *%w[plastic.db work_graph.db knowledge_graph.db retrieval_graph.db].map { |name| ["database", name, name] },
      *%w[command_runs sessions intents nodes runs edges documents rulings links sqlar].map { |name| ["table", name, name] },
      *%w[store/index.json spec.md graph.json work.log outcome.md context.json].map { |name| ["store_file", name, name] },
      ["command", "sync up", "sync up"]
    ].freeze

    def self.diagrams = [Diagram.new(META, BOXES, ARROWS)]

    def self.files = Diagram.merge(diagrams)

    def self.names = NAMES
  end
end
