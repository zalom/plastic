# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../../varar/support/kernel_command"

class SyncUpGraphTest < Minitest::Test
  DIR = "store/1--prove-the-resume"
  GRAPH = "#{DIR}/graph.json"
  DATABASE_FILE = /\.db(-wal|-shm|-journal)?\z/
  SPEC = "# Spec\n\n## Goal\n\nProve the resume.\n\n## Done criteria\n\n- [ ] [proof] The graph continues on another machine.\n"

  def first_home(kernel)
    kernel.run!("intent", "new", "Prove the resume")
    kernel.write("#{DIR}/spec.md", SPEC)
    kernel.run!("sync", "up")
    kernel.run!("node", "add", "1", "Write the test", "--criterion", "proof")
    kernel.run!("node", "add", "1", "Write the code", "--criterion", "proof")
    kernel.run!("edge", "add", "1", "n1", "n2")
    kernel.run!("intent", "approve", "1")
    kernel.run!("node", "claim", "1", "n1")
    kernel.run!("node", "done", "1", "n1", "The test is red for the right reason")
  end

  def move_files(from, to)
    FileUtils.rm_rf(to.store)
    from.snapshot("").each do |rel, bytes|
      next if rel.match?(DATABASE_FILE)

      to.write(rel, bytes)
    end
  end

  def nodes(kernel) = kernel.rows("work_graph.db", "SELECT id, state, by, retries, updated_at FROM nodes ORDER BY id")

  def with_two_homes
    Dir.mktmpdir do |one|
      Dir.mktmpdir do |two|
        first, second = KernelCommand.new(one), KernelCommand.new(two)
        first_home(first)
        move_files(first, second)
        yield first, second
      end
    end
  end

  def test_the_graph_of_one_machine_continues_on_a_second_home_after_sync_up
    with_two_homes do |first, second|
      second.run!("sync", "up")

      assert_equal nodes(first), nodes(second)
      assert_equal first.rows("work_graph.db", "SELECT count(*) FROM edges"), second.rows("work_graph.db", "SELECT count(*) FROM edges")
      assert_equal first.rows("work_graph.db", "SELECT count(*) FROM approvals"), second.rows("work_graph.db", "SELECT count(*) FROM approvals")
      assert_equal first.rows("work_graph.db", "SELECT status FROM intents"), second.rows("work_graph.db", "SELECT status FROM intents")
      assert_equal [second.origin], second.rows("work_graph.db", "SELECT DISTINCT origin_id FROM nodes").flatten
    end
  end

  def test_a_second_sync_up_leaves_graph_json_and_its_printed_hash_as_they_are
    with_two_homes do |first, second|
      second.run!("sync", "up")
      bytes = second.read(GRAPH)
      printed = second.rows("work_graph.db", "SELECT sha256 FROM printed WHERE path = '#{GRAPH}'")
      second.run!("sync", "up")

      assert_equal bytes, first.read(GRAPH)
      assert_equal [bytes, printed], [second.read(GRAPH), second.rows("work_graph.db", "SELECT sha256 FROM printed WHERE path = '#{GRAPH}'")]
    end
  end

  def test_the_second_home_can_claim_the_next_node_of_the_graph
    with_two_homes do |_first, second|
      second.run!("sync", "up")

      assert_includes second.run!("node", "claim", "1", "n2").out, "n2"
    end
  end
end
