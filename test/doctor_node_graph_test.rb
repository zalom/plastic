# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"

# The doctor rule over ReadySet (intent 336, n7): dead ends, stale done nodes,
# and expired running leases, reported across every intent carrying a real
# graph.md. Lives in scripts/doctor.rb, never doctor_core.rb, because
# test/doctor_core_split_test.rb pins the boot path to exactly three project
# files and 781 bytes of headroom - ReadySet's own require chain is far
# larger than that. Hermetic: every fixture lives in a Dir.mktmpdir.
class DoctorNodeGraphTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-node-graph")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    write_index
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_index
    FileUtils.mkdir_p(@home)
    File.write(File.join(@home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n\n## Clusters\n\n" \
                                              "## Abandoned\n\n## Completed\n\n## Relocated\n(none)\n")
  end

  def write_intent(id, graph_body: nil, nodes: {}, savepoint: nil)
    dir = File.join(@store, "#{id}--demo")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--demo.md"), "---\nid: \"#{id}\"\nintent: t\n---\n\n## Intent\nb\n")
    File.write(File.join(dir, "graph.md"), graph_body) if graph_body
    if nodes.any?
      FileUtils.mkdir_p(File.join(dir, "nodes"))
      nodes.each do |node_id, kind|
        File.write(File.join(dir, "nodes", "#{node_id}.md"), <<~MD)
          ---
          node: #{node_id}
          kind: #{kind}
          files: []
          budget: 1000
          ---
          # #{node_id}

          ## Steps
          1. go

          ## Proven by
          (later)
        MD
      end
    end
    File.write(File.join(dir, "savepoint.md"), savepoint) if savepoint
    dir
  end

  def doctor = Doctor.new(plastic_home: @home)

  def check(name)
    doctor.check_conventions.find { |c| c[:name] == name }
  end

  def test_the_rule_lives_outside_the_boot_path
    write_intent("1", graph_body: "## Graph\n- n1 needs nothing\n", nodes: { "n1" => "work" })
    refute_nil check("node_graph_dead_ends"),
               "the node-graph doctor rule must run from the full scripts/doctor.rb path " \
               "(test/doctor_core_split_test.rb proves it never attaches to doctor_core.rb's boot path)"
  end

  def test_doctor_reports_a_dead_end
    write_intent("1", graph_body: "## Graph\n- n1 needs nothing\n- n2 needs n1\n",
                       nodes: { "n1" => "work", "n2" => "work" },
                       savepoint: "2026-09-09T10:00:00Z  n1  abandoned reason=cut\n")
    result = check("node_graph_dead_ends")
    assert_equal "warn", result[:status]
    assert(result[:details].any? { |d| d.include?("1--demo") && d.include?("n2") })
  end

  def test_doctor_reports_a_stale_done_node
    write_intent("1", graph_body: "## Graph\n- n1 needs nothing\n- n2 needs n1\n",
                       nodes: { "n1" => "work", "n2" => "work" },
                       savepoint: "2026-09-09T10:00:00Z  n1  done gates=g1 commit=c1 holder=h\n" \
                                  "2026-09-09T10:01:00Z  n2  done gates=g1 commit=c1 holder=h\n" \
                                  "2026-09-09T10:02:00Z  n1  superseded by=n9\n")
    result = check("node_graph_stale_done")
    assert_equal "warn", result[:status]
    assert(result[:details].any? { |d| d.include?("1--demo") && d.include?("n2") })
  end

  def test_doctor_reports_an_expired_running_lease
    write_intent("1", graph_body: "## Graph\n- n1 needs nothing\n", nodes: { "n1" => "work" },
                       savepoint: "2020-01-01T00:00:00Z  n1  running holder=h expires=2020-01-01T00:05:00Z " \
                                  "packet=p model=m\n")
    result = check("node_graph_expired_running_lease")
    assert_equal "warn", result[:status]
    assert(result[:details].any? { |d| d.include?("1--demo") && d.include?("n1") })
  end

  def test_doctor_rule_skips_intents_without_a_graph
    write_intent("1")
    assert_equal "pass", check("node_graph_dead_ends")[:status]
    assert_equal "pass", check("node_graph_malformed")[:status]
  end

  def test_doctor_rule_reports_a_malformed_graph
    write_intent("1", graph_body: "## Graph\n- n1 needs n2\n- n2 needs n1\n", nodes: { "n1" => "work", "n2" => "work" })
    result = check("node_graph_malformed")
    assert_equal "warn", result[:status]
    assert(result[:details].any? { |d| d.include?("1--demo") })
  end
end
