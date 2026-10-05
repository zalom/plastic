# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/retrieval/evidence/writer"
require "timeout"

class RetrievalRepairSnapshotTest < Plastic::TestCase
  def test_repair_holds_an_immediate_snapshot_against_a_second_connection
    process, acquired = repair_with_blocked_writer

    assert_equal "acquired", Timeout.timeout(1) { acquired.read }
    Process.wait(process)
    process = nil
  ensure
    Process.wait(process) if process
    close_pipes
  end

  private

  def repair_with_blocked_writer
    isolated_writer.write("1", "repair.md", "repair evidence")
    isolated.transaction { |batch| batch.add("DELETE FROM document_fts") }
    @pipes = IO.pipe + IO.pipe
    repairer = Plastic::Graph::Retrieval::Evidence::Integrity.new(isolated, origin, before_rebuild: method(:block_writer))
    repairer.repair
    [@writer, acquired]
  end

  def block_writer
    @writer = fork { concurrent_update }
    attempted_writer.close
    acquired_writer.close

    assert_equal "attempted", Timeout.timeout(1) { attempted.read(9) }
    assert_nil IO.select([acquired], nil, nil, 0.1)
  end

  def concurrent_update
    attempted.close
    acquired.close
    attempted_writer.write("attempted")
    with_isolated_connection { |connection| begin_and_update(connection) }
  ensure
    close_pipes
    exit!
  end

  def with_isolated_connection
    connection = Plastic::Graph::Database::Connection.open(isolated.path)
    yield connection
  ensure
    connection&.close
  end

  def update_isolated_document(connection)
    connection.execute("UPDATE documents SET updated_at = 'after' WHERE origin_id = ?", [origin])
    connection.commit
  end

  def begin_and_update(connection)
    connection.execute("BEGIN IMMEDIATE")
    acquired_writer.write("acquired")
    update_isolated_document(connection)
  end

  def close_pipes
    @pipes.to_a.each { |pipe| pipe.close unless pipe.closed? }
  end

  def attempted = @pipes.fetch(0)
  def attempted_writer = @pipes.fetch(1)
  def acquired = @pipes.fetch(2)
  def acquired_writer = @pipes.fetch(3)
  def isolated = (@isolated ||= Plastic::Graph::Database.new(File.join(@home, "isolated", "knowledge_graph.db"), Plastic::Graph::Schema.fetch(:knowledge), origin: Plastic::Graph::Origin.new(@plastic_home)))
  def isolated_writer = Plastic::Graph::Retrieval::Evidence::Writer.new(isolated, origin)
end
