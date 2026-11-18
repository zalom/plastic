# frozen_string_literal: true

require "json"
require_relative "two_homes_helper"

# The links of store/index.json that the tests of two homes change, and the reads of their rows.
module TwoHomesLinksHelper
  include TwoHomesHelper

  FILE = "store/index.json"
  PART = "store/index.json#links"
  CITES = %w[2 1 cites].freeze

  def seed(home)
    %w[Alpha Beta].each { |title| call_in(home, "intent", "new", title) }
  end

  def to_both_homes(&) = two_homes(seed: method(:seed), &)

  def link(home, from, kind, to) = call_in(home, "intent", "link", from, kind, to)

  def unlink(home, from, kind, to) = call_in(home, "intent", "unlink", from, kind, to)

  # One link row on a home, with the origin of that home unless `origin` names another, and no print of the index.
  def put_link(home, from, kind, to, origin: nil)
    row = { from_ref: from, to_ref: to, kind:, at: Plastic::TestCase::STAMP }
    database_of(home).transaction { |batch| batch.put(:links, origin ? row.merge(origin_id: origin) : row) }
  end

  def links(home, origin: origin_of(home))
    rows_of(home, "SELECT from_ref, to_ref, kind FROM links WHERE origin_id = :origin ORDER BY from_ref, to_ref, kind", origin:)
      .map { |row| row.values_at("from_ref", "to_ref", "kind") }
  end

  def listed(home) = JSON.parse(read_file(home, FILE))["links"]

  def listed_keys(home) = Array(listed(home)).map { |entry| entry.values_at("from_ref", "to_ref", "kind") }

  def printed_part?(home) = home_graphs(home).retrieval.stored.printed.key?(PART)

  def forget_part(home) = database_of(home).transaction { |batch| batch.remove(:printed, path: PART) }

  def write_links_part(home, links)
    data = JSON.parse(read_file(home, FILE))
    write_file(home, FILE, JSON.pretty_generate(links ? data.merge("links" => links) : data.except("links")))
  end

  def said(call) = call.out + call.err
end
