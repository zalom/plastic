# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "kernel_command"

module TwoHomes
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
    kernel.run!("node", "done", "1", "n1", "The test is red for the right reason; see :id and :intent_id")
    kernel.run!("intent", "verdict", "1", "revise", "The findings hold :id and :intent_id")
  end

  def move_files(from, to)
    FileUtils.rm_rf(to.store)
    from.snapshot("").each do |rel, bytes|
      next if rel.match?(DATABASE_FILE)

      to.write(rel, bytes)
    end
  end

  def nodes(kernel) = kernel.rows("work_graph.db", "SELECT id, state, by, retries, updated_at, findings FROM nodes ORDER BY id")

  def query(kernel, sql) = kernel.rows("work_graph.db", sql)

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

  def unstamped(text) = JSON.parse(text).then { |data| JSON.generate(strip_origin(data)) }

  def strip_origin(data)
    case data
    when Hash then data.except("origin_id").transform_values { |value| strip_origin(value) }
    when Array then data.map { |value| strip_origin(value) }
    else data
    end
  end
end
