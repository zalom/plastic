# frozen_string_literal: true

require "varar"
require "tmpdir"
require_relative "support/kernel_command"

# Builds intent 1 through a full pass of the work graph and names the
# pattern each check's output lines match.
module WorkGraphAcceptance
  CHECKS = {
    "graph show 1" => /\A(?:node|edge):/,
    "intent brief 1" => /\A(?:ruling|ready):/
  }.freeze

  RULINGS = [
    %w[intent new Alpha],
    ["intent", "rule", "1", "Flowbite styles every delivery"],
    ["intent", "rule", "1", "Direct mode only", "--supersedes", "D1"]
  ].freeze

  NODES_AND_EDGE = [
    ["node", "add", "1", "do the thing", "--criterion", "it is done"],
    ["node", "add", "1", "build it", "--criterion", "it builds"],
    %w[edge add 1 n1 n2]
  ].freeze

  NODE_LIFECYCLE = [
    %w[node claim 1 n1],
    ["node", "fail", "1", "n1", "--reason", "broke"],
    %w[node release 1 n1],
    %w[node claim 1 n1],
    ["node", "done", "1", "n1", "--judge", "tests", "--findings", "it passed"]
  ].freeze

  # Opens the intent and runs every call of the narrative in order: the
  # rulings, the nodes and the edge, then the node's claim-fail-release-
  # claim-done cycle.
  def self.build(kernel)
    [*RULINGS, *NODES_AND_EDGE, *NODE_LIFECYCLE].each { |args| kernel.run!(*args) }
  end
end

steps do
  sensor("the check, the exit code and what it shows") do |_state, row|
    Dir.mktmpdir("varar-work-graph") do |home|
      kernel = KernelCommand.new(home)
      WorkGraphAcceptance.build(kernel)
      call = kernel.run(*row["check"].split)
      pattern = WorkGraphAcceptance::CHECKS.fetch(row["check"])
      row.merge("exit" => call.code.to_s, "shows" => call.said.grep(pattern).join(", "))
    end
  end
end
