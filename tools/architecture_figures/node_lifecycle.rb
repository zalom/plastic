# frozen_string_literal: true

require_relative "diagram"

module ArchitectureFigures
  # The states of a work node. See docs/contributing/ARCHITECTURE.md.
  module NodeLifecycle
    META = Diagram::Meta.new(file: "node-lifecycle.svg", width: 1160, height: 520, title: "How a node moves through its states",
      desc: "node add writes an open node. The main session claims it with node claim as it dispatches the agent, and the claim keeps the delivery lock live. node done records the judged report. node fail, node ask and node impede stop the node, and node release or node resolve reopens it. node remove takes an open node out of the graph.")
    BOXES = Diagram.parse(<<~TABLE).freeze
      removed | | 30 30 220 | removed | Gone | line | | Only an open node. It / leaves the graph.
      lock | | 350 30 260 | Delivery lock | row in local.db | code | | Live while renewed within 1800 s, / or while a node of its session / is claimed within 7200 s.
      open | | 30 200 220 | open | 1  Added | line | | The main session writes it / with node add, keyed to the / done criterion it serves.
      claimed | | 350 200 260 | claimed | 2  Dispatched | agent | | The main session claims it as / it dispatches the agent. The / claim keeps the lock live.
      done | | 900 200 230 | done | 3  Judged | end | | The main session judges the / report and records its / findings.
      failed | | 30 400 220 | failed | Stopped | agent | | node release reopens it.
      needs_info | | 350 400 260 | needs_info | Waiting on the owner | owner | | node resolve reopens it / with the answer.
      impeded | | 690 400 260 | impeded | Blocked | owner | | node resolve reopens it / once the impediment clears.
    TABLE
    ARROWS = [
      ["open.top", "removed.bottom", ["node remove"]],
      ["open.right", "claimed.left", ["node claim"]],
      ["claimed.right", "done.left", ["node done"]],
      ["claimed.top", "lock.bottom", ["keeps live"], true],
      ["claimed.bottom@0.2", "failed.top", ["node fail"]],
      ["claimed.bottom", "needs_info.top", ["node ask"]],
      ["claimed.bottom@0.8", "impeded.top", ["node impede"]]
    ].freeze
    COMMANDS = ["node add", "node claim", "node done", "node fail", "node ask", "node impede", "node release", "node resolve", "node remove"].freeze

    def self.diagrams = [Diagram.new(META, BOXES, ARROWS)]

    def self.files = Diagram.merge(diagrams)

    def self.names = COMMANDS.map { |name| ["command", name, name] }
  end
end
