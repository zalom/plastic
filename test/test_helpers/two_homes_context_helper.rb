# frozen_string_literal: true

require "json"
require_relative "two_homes_helper"

# The context of intent 1 that the tests of two homes change, and the reads of its rows.
module TwoHomesContextHelper
  include TwoHomesHelper

  FILE = "store/1--alpha/context.json"
  TABLES = { "context" => :retrieval_contexts, "discovery" => :retrieval_discoveries }.freeze

  def seed(home)
    call_in(home, "intent", "new", "Alpha")
    put_part(home, "context", { "note" => "first" })
    put_part(home, "discovery", { "terms" => ["first"] })
  end

  def to_both_homes(&) = two_homes(seed: method(:seed), &)

  # Puts one part of the context as a row, with the origin of that home unless `origin` names another.
  def put_part(home, part, data, origin: nil)
    row = { intent_id: "1", data: JSON.pretty_generate(data), updated_at: Plastic::TestCase::STAMP }
    database_of(home, :knowledge).transaction { |batch| batch.put(TABLES.fetch(part), origin ? row.merge(origin_id: origin) : row) }
  end

  # A change of the context on a home through its rows, printed to the file by sync down.
  def change_part(home, part, data)
    put_part(home, part, data)
    call_in(home, "sync", "down")
  end

  def part_of(home, part, origin: origin_of(home))
    row = rows_of(home, :knowledge, "SELECT data FROM #{TABLES.fetch(part)} WHERE intent_id = '1' AND origin_id = :origin", origin:).first
    row && JSON.parse(row["data"])
  end

  def file_part(home, part) = JSON.parse(read_file(home, FILE))[part]

  def said(call) = call.out + call.err
end
