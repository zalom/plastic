# frozen_string_literal: true

require "json"
require_relative "two_homes_helper"

# The clusters of store/index.json that the tests of two homes change, and the reads of their rows.
module TwoHomesClusterHelper
  include TwoHomesHelper

  FILE = "store/index.json"
  PART = "store/index.json#clusters"

  def seed(home)
    %w[Alpha Beta].each { |title| call_in(home, "intent", "new", title) }
    put_cluster(home, "one", "1")
  end

  def to_both_homes(&) = two_homes(seed: method(:seed), &)

  # Puts one cluster row, with the origin of that home unless `origin` names another.
  def put_cluster(home, name, intent_id, origin: nil)
    row = { name:, intent_id: }
    database_of(home).transaction { |batch| batch.put(:clusters, origin ? row.merge(origin_id: origin) : row) }
  end

  # A change of the clusters on a home through its rows, printed to the file by sync down.
  def change_clusters(home, name, intent_id)
    put_cluster(home, name, intent_id)
    call_in(home, "store", "sync", "down")
  end

  def clusters(home, origin: origin_of(home))
    rows_of(home, "SELECT name, intent_id FROM clusters WHERE origin_id = :origin ORDER BY name, intent_id", origin:).map { |row| [row["name"], row["intent_id"]] }
  end

  def listed(home) = JSON.parse(read_file(home, FILE)).fetch("clusters").map { |cluster| cluster["name"] }.sort

  def printed_part?(home) = home_graphs(home).retrieval.stored.printed.key?(PART)

  def said(call) = call.out + call.err
end
