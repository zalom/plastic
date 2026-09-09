# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/ready_set"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/lock"
load File.expand_path("../scripts/node-transition", __dir__)

# node-transition refuses through ReadySet (intent 336, n5). Matrix rows in
# actions/ACTION_1.md n5. The temporary NodeLedger.needs_from_graph reader
# 335 shipped naming this intent as its replacement is deleted along with
# the four tests that pinned it (test/node_ledger_test.rb:369-430); the
# cases they covered (a missing graph.md returns no needs, both the 334 and
# the temporary edge grammars, the "nothing"/"none" root spellings) move
# into #test_edges_come_from_graph_file below, now read through GraphFile.
class NodeTransitionReadySetTest < Minitest::Test
  NODE_TRANSITION = File.expand_path("../scripts/node-transition", __dir__)

  RUNNING_FIELDS = { holder: "auto-owner", expires: "2026-09-09T20:00:00Z", packet: "abc123", model: "sonnet" }.freeze

  def setup
    @home = Dir.mktmpdir("node-transition-ready-set")
    @intent_dir = build_intent_dir(@home)
    @savepoint_path = File.join(@intent_dir, "savepoint.md")
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixtures -----------------------------------------------------------------

  def build_intent_dir(home, id: "1", slug: "demo")
    dir = File.join(home, "store", "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--#{slug}.md"),
               "---\nid: \"#{id}\"\nintent: \"t\"\n---\n\n## Intent\nbody\n")
    dir
  end

  def write_lock(dir, owner:, delegates: [])
    File.write(File.join(dir, "delivery.lock"),
               JSON.generate("type" => "delivery", "owner_session" => owner, "delegates" => delegates))
  end

  def write_graph(graph_body)
    File.write(File.join(@intent_dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  def write_node(id, kind: "work", files: [])
    File.write(File.join(@intent_dir, "nodes", "#{id}.md"), <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: #{files.inspect}
      budget: 100000
      ---
      # #{id} - a node

      ## #{id} failure-mode matrix
      | Operation | Failure mode | Test |
      | --- | --- | --- |
      | op | mode | a test |

      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD
  end

  def append_line(dir, subject:, state:, fields: {}, comment: nil, now: Time.utc(2026, 9, 9, 18, 0, 0))
    line = NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: now)
    File.open(File.join(dir, "savepoint.md"), "a") { |io| io.write(line) }
  end

  def running_field_args(fields = RUNNING_FIELDS)
    fields.flat_map { |k, v| ["--field", "#{k}=#{v}"] }
  end

  def run_cli(*args, env: {})
    full_env = { "CLAUDE_CODE_SESSION_ID" => nil }.merge(env)
    Open3.capture3(full_env, RbConfig.ruby, NODE_TRANSITION, *args)
  end

  # --- readiness through the four conditions ------------------------------------

  def test_running_refused_when_a_need_is_not_done
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    write_lock(@intent_dir, owner: "sess-a")
    out, err, status = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 5, status.exitstatus, out + err
    assert_match(/n1/, err)
  end

  def test_running_refused_when_a_sibling_holds_the_file
    write_graph("- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1", files: ["scripts/lib/x.rb"])
    write_node("n2", files: ["scripts/lib/x.rb"])
    write_lock(@intent_dir, owner: "sess-a")
    append_line(@intent_dir, subject: "n2", state: "running", fields: RUNNING_FIELDS)
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 5, status.exitstatus, out + err
  end

  def test_running_refused_at_the_dispatch_cap
    write_graph("- n1 needs nothing\n")
    write_node("n1")
    write_lock(@intent_dir, owner: "sess-a")
    3.times do |i|
      append_line(@intent_dir, subject: "n1", state: "running",
                  fields: { holder: "auto-#{i}", expires: "2026-09-09T20:00:00Z", packet: "p", model: "m" })
      append_line(@intent_dir, subject: "n1", state: "reclaimed",
                  fields: { holder: "auto-#{i}", expired: "2026-09-09T20:00:00Z" })
    end
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 5, status.exitstatus, out + err
    assert_match(/cap/, err)
  end

  def test_running_refused_behind_a_dead_end
    write_graph("- n1 needs nothing\n- n2 needs n1\n- n3 needs n2\n")
    write_node("n1")
    write_node("n2")
    write_node("n3")
    write_lock(@intent_dir, owner: "sess-a")
    append_line(@intent_dir, subject: "n1", state: "abandoned", fields: { reason: "cut" })
    out, err, status = run_cli(@intent_dir, "--node", "n3", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 5, status.exitstatus, out + err
    assert_match(/dead end/, err, "the dead-end condition must contribute its own named blocker")
  end

  def test_readiness_refusals_all_exit_five
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    write_lock(@intent_dir, owner: "sess-a")
    _out, _err, status = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                  *running_field_args)
    assert_equal 5, status.exitstatus
  end

  # --- the parse-once, guard-hold contract (R-5) --------------------------------

  def test_graph_and_nodes_are_parsed_once_before_the_guard
    write_graph("- n1 needs nothing\n")
    write_node("n1")
    write_lock(@intent_dir, owner: "sess-a")

    count = 0
    original = ReadySet.method(:load_graph)
    ReadySet.define_singleton_method(:load_graph) do |*a|
      count += 1
      original.call(*a)
    end
    begin
      begin
        NodeTransition.main([@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                              *running_field_args])
      rescue SystemExit
        nil
      end
    ensure
      ReadySet.define_singleton_method(:load_graph, original)
    end
    assert_equal 1, count, "graph.md/nodes/ must be parsed exactly once, never re-read inside the guard's hold"
  end

  def test_readiness_precondition_runs_against_guard_content
    edges = { "n1" => [], "n2" => [] }
    nodes = { "n1" => { kind: "work", files: ["a.rb"] }, "n2" => { kind: "work", files: ["a.rb"] } }
    precondition = ->(content) { NodeTransition.running_ready?(content, "n1", edges, nodes)[:ready] }

    assert precondition.call(""), "no sibling running yet: n1 must be ready"

    n2_running = NodeLedger.transition_line(subject: "n2", state: "running",
                                             fields: { holder: "h", expires: "2026-09-09T20:00:00Z",
                                                       packet: "p", model: "m" })
    refute precondition.call(n2_running),
           "the SAME precondition object must re-derive readiness from whatever content it is given, " \
           "never a value captured before the call"
  end

  def test_four_concurrent_writers_land_one_running_line
    rounds = 10
    writers = 4

    rounds.times do |round|
      home = Dir.mktmpdir("node-transition-race-rs")
      begin
        intent_dir = build_intent_dir(home)
        FileUtils.mkdir_p(File.join(intent_dir, "nodes"))
        File.write(File.join(intent_dir, "graph.md"), <<~MD)
          # Graph

          ## Graph
          - n1 needs nothing

          ## Status
        MD
        File.write(File.join(intent_dir, "nodes", "n1.md"), <<~MD)
          ---
          node: n1
          kind: work
          files: []
          budget: 1000
          ---
          # n1

          ## Steps
          1. go

          ## Proven by
          (later)
        MD
        write_lock(intent_dir, owner: "sess-a")
        savepoint_path = File.join(intent_dir, "savepoint.md")
        args = [intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a"] + running_field_args

        pids = Array.new(writers) do
          fork do
            $PROGRAM_NAME = "node-transition-rs-race-child"
            $stdout.reopen(File::NULL, "w")
            $stderr.reopen(File::NULL, "w")
            load NODE_TRANSITION
            status = begin
              NodeTransition.main(args)
              0
            rescue SystemExit => e
              e.status
            end
            exit!(status)
          end
        end
        pids.each { |pid| Process.waitpid(pid) }

        running_lines = File.exist?(savepoint_path) ? File.readlines(savepoint_path).grep(/  running /) : []
        assert_equal 1, running_lines.length,
                     "round #{round}: expected exactly one running line, got #{running_lines.length}"
      ensure
        FileUtils.remove_entry(home)
      end
    end
  end

  # --- one parser for graph.md ---------------------------------------------------

  def test_edges_come_from_graph_file
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    write_lock(@intent_dir, owner: "sess-a")

    out, err, status = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 5, status.exitstatus, out + err

    append_line(@intent_dir, subject: "n1", state: "done", fields: { gates: "suite", commit: "abc", holder: "h" })
    _out, err2, status2 = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                   *running_field_args)
    assert_equal 0, status2.exitstatus, err2
  end

  def test_explicit_needs_flag_still_wins
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    write_lock(@intent_dir, owner: "sess-a")
    # n1 is never done, so the graph would refuse; an explicit empty --needs
    # must override the graph entirely.
    _out, err, status = run_cli(@intent_dir, "--node", "n2", "--state", "running", "--session", "sess-a",
                                 "--needs", "", *running_field_args)
    assert_equal 0, status.exitstatus, err
  end

  def test_needs_from_graph_no_longer_exists
    refute NodeLedger.respond_to?(:needs_from_graph),
           "the temporary needs_from_graph reader must be deleted; GraphFile is the one parser"
  end

  # --- legacy and intent-scope handling -------------------------------------------

  def test_cyclic_graph_refuses_with_a_message_not_a_raise
    # A cyclic graph.md is present but unusable - node-transition must refuse
    # cleanly (a message, exit 5), never raise out with a Ruby backtrace.
    write_graph("- n1 needs n2\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    write_lock(@intent_dir, owner: "sess-a")
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 5, status.exitstatus, out + err
    refute_match(/\.rb:\d+:in/, err, "must not raise a Ruby backtrace")
  end

  # Finding 6: the previous test above exercised a present-but-cyclic
  # graph.md, never the genuinely absent case. A legacy intent with NO
  # graph.md at all must keep dispatching (335's shipped behavior):
  # resolve_graph_and_nodes degrades to {edges: {}, nodes: {}}, so the needs
  # condition is vacuous and the node's kind is nil - which, since finding
  # 1a, falls back to the work cap rather than skipping the cap check
  # entirely. It works up to that cap, then is refused at it.
  def test_transition_with_no_graph_md_dispatches_up_to_the_work_cap
    write_lock(@intent_dir, owner: "sess-a")
    3.times do |i|
      out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                  *running_field_args)
      assert_equal 0, status.exitstatus, "attempt #{i}: #{out}#{err}"
      append_line(@intent_dir, subject: "n1", state: "reclaimed",
                  fields: { holder: "auto-owner", expired: "2026-09-09T20:00:00Z" })
    end
    out, err, status = run_cli(@intent_dir, "--node", "n1", "--state", "running", "--session", "sess-a",
                                *running_field_args)
    assert_equal 5, status.exitstatus, out + err
    assert_match(/cap/, err)
  end

  def test_intent_subject_is_not_subject_to_node_readiness
    # No graph.md at all: an Intent-scope line must still be writable.
    write_lock(@intent_dir, owner: "sess-a")
    _out, err, status = run_cli(@intent_dir, "--node", "Intent", "--state", "running", "--session", "sess-a",
                                 *running_field_args)
    assert_equal 0, status.exitstatus, err
  end
end
