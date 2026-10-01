# frozen_string_literal: true

require_relative "../../test_helper"

class PrinterTest < Plastic::TestCase
  Print = Plastic::Graph::Prints::Print

  def printer = Plastic::Graph::Printer.new(folder, store_graphs.databases, retrieval)

  # A database that keeps the rows each put_all gives it.
  class Recording
    attr_reader :rows

    def initialize = @rows = []

    def transaction = yield(self)

    def put_all(table, rows) = @rows << [table, rows.map { |row| row[:path] }]
  end

  def test_print_writes_the_files_that_differ_and_returns_their_paths
    write("a.md", "same\n")
    prints = [Print.text("a.md", :knowledge, "same\n"), Print.text("b.md", :work, "new\n")]

    assert_equal ["b.md"], printer.print(prints)
    assert_equal "new\n", folder.read("b.md")
  end

  def test_print_records_every_hash_in_the_database_that_owns_it
    printer.print([Print.text("a.md", :knowledge, "x"), Print.text("b.md", :work, "y")])

    assert_equal({ "b.md" => Digest::SHA256.hexdigest("y"), "a.md" => Digest::SHA256.hexdigest("x") }, retrieval.printed)
  end

  def test_record_skips_a_hash_already_recorded
    database = Recording.new
    recorded = Data.define(:printed).new({ "a.md" => Digest::SHA256.hexdigest("x") })
    Plastic::Graph::Printer.new(folder, { knowledge: database }, recorded).record([Print.text("a.md", :knowledge, "x"),
      Print.text("b.md", :knowledge, "y")])

    assert_equal [[:printed, ["b.md"]]], database.rows
  end

  def test_record_with_nothing_to_record_writes_nothing
    assert_empty printer.record([])
  end
end
