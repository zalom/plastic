# frozen_string_literal: true

require "varar"
require "json"
require "fileutils"
require "tmpdir"
require_relative "support/kernel_command"
require_relative "../test_helpers/two_homes"

module SyncSecondHomeAcceptance
  extend TwoHomes

  def self.home_command(directory) = KernelCommand.new(directory)

  QUERIES = {
    "nodes with their states" => "SELECT id, state, claimed_by, answered_at, updated_at FROM nodes ORDER BY id",
    "edges" => "SELECT \"from\", \"to\", kind FROM edges ORDER BY \"from\", \"to\"",
    "verdicts" => "SELECT round, verdict, findings FROM verdicts ORDER BY round",
    "findings of a node" => "SELECT id, findings FROM nodes ORDER BY id"
  }.freeze

  def self.same?(state)
    with_two_homes do |first, second|
      second.command!("store", "sync", "up")
      sql = QUERIES.fetch(state)
      rows = query(first, sql)
      (rows.any? && rows == query(second, sql)) ? "equal" : "different"
    end
  end
end

steps do
  sensor("the state and the comparison of the two homes") do |_state, row|
    row.merge("comparison" => SyncSecondHomeAcceptance.same?(row["state"]))
  end
end
