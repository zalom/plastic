# frozen_string_literal: true

# What the tests of a second home share: a context that a home holds as a file and no row.
module SecondHomeHelper
  CONTEXT = "store/1--alpha/context.json"
  STAMP = Plastic::TestCase::STAMP

  def work = store_graphs.databases.fetch(:store)

  def sync = (@sync ||= Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases))

  def plan = sync.plan(:up)

  def run_up = sync.apply(plan)

  def context_json(**fields) = JSON.generate({ "intent" => "1", "discovery" => { "a" => 1 }, "context" => { "b" => 2 } }.merge(fields.transform_keys(&:to_s)))
end
