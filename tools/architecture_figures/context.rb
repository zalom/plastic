# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Context
    META = Diagram::Meta.new(file: "context.svg", width: 1160, height: 372, title: "Plastic and what it talks to",
      desc: "The owner gives goals to an agent harness. The harness runs plastic commands and fires hook events. Plastic reads where each project lives and keeps its work as rows. The harness edits the project repositories and pushes to GitHub, where the owner reviews and merges the pull request.")
    BOXES = Diagram.parse(<<~TABLE).freeze
      owner | | 30 30 250 | Owner | person | owner | | Decides what to build and gives / the go-ahead to deliver it.
      harness | | 30 205 250 | Agent harness | software | agent | | Claude Code or Codex: runs the / agent and fires the hook events.
      plastic | | 440 190 280 | Plastic | software system | code | | The plastic command and its hooks. / Keeps the work of every intent as / rows in SQLite files, one store for / each project. Runs no git command.
      repos | | 880 205 250 | Project repositories | software | line | | The code. The agent edits it in a / worktree made for each intent.
      github | | 880 30 250 | GitHub | external system | end | | Holds the pull request and runs / the tests in CI.
    TABLE
    ARROWS = [
      ["owner.right", "github.left", ["reviews and merges the pull request"]],
      ["owner.bottom", "harness.top", ["goals, answers,", "go-ahead"]],
      ["harness.right", "plastic.left", ["plastic commands;", "hook events"]],
      ["plastic.right", "repos.left", ["reads where each", "project lives"], true],
      ["repos.top", "github.bottom", ["git push,", "pull request"]]
    ].freeze
    EXTRAS = [Shapes::Key.new(left: 30, top: 350, items: [[:owner, "person"], [:agent, "agent harness"], [:code, "Plastic"], [:line, "project code"], [:end, "outside system"]])].freeze
    NAMES = [].freeze

    def self.diagrams = [Diagram.new(META, BOXES, ARROWS, EXTRAS)]

    def self.files = Diagram.merge(diagrams)

    def self.names = NAMES
  end
end
