# frozen_string_literal: true

require "json"
require_relative "two_homes_helper"

# The title and the state of the intents that the tests of two homes change, and the reads of their rows.
module TwoHomesStatusHelper
  include TwoHomesHelper

  FILE = "store/index.json"
  CLOSED = { status: "done", disposition: "delivered", reason: "shipped on A", closed_at: "2026-10-05T08:00:00Z" }.freeze

  def seed(home)
    %w[Alpha Beta].each { |title| call_in(home, "intent", "new", title) }
  end

  def to_both_homes(&) = two_homes(seed: method(:seed), &)

  def intent_row(home, intent_id, origin: origin_of(home))
    rows_of(home, "SELECT * FROM intents WHERE intent_id = :id AND origin_id = :origin", id: intent_id, origin:).first
  end

  def fields(home, intent_id) = intent_row(home, intent_id).slice("title", "status", "disposition", "reason", "closed_at")

  # A change of the row of an intent on a home, printed to the file by sync down.
  def change_row(home, intent_id, **changes)
    row = home_graphs(home).retrieval.intent(intent_id).new_row.merge(changes)
    database_of(home).transaction { |batch| batch.put(:intents, row) }
    call_in(home, "sync", "down")
  end

  def list_first_intent_of_a_third_origin(home)
    data = index_of(home)
    data["intents"].first["origin_id"] = "zzzz"
    write_file(home, FILE, JSON.pretty_generate(data))
  end

  def index_of(home) = JSON.parse(read_file(home, FILE))

  def said(call) = call.out + call.err
end
