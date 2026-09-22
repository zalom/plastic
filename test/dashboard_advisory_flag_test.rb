# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "json"

# The dashboard's ReadySet read (intent 336, n7, D14): a graph-shaped
# intent's ready node count, explicitly advisory and entirely separate from
# the sources-derived "unblocked" flag, which stays exactly where it is
# (327 D40). ReadySet.analyze is called only for an intent with a real
# graph.md - never for the other 448. Subprocess-based, matching
# test/dashboard_test.rb's own hermeticity pattern (PLASTIC_HOME is a
# module-level constant baked in at first require, so every dashboard test
# spawns a fresh process rather than requiring the file in-process).
class DashboardAdvisoryFlagTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/dashboard.rb", __dir__)
  TODAY = "2026-09-09"

  def setup
    @home = Dir.mktmpdir("plastic-dash-ready-set")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && File.directory?(@home)
  end

  def run_dash(*args)
    env = { "PLASTIC_HOME" => @home, "DASHBOARD_TODAY" => TODAY }
    out = IO.popen(env, ["ruby", SCRIPT, *args], &:read)
    [out, $?.exitstatus]
  end

  def write_intent(store, id, slug, frontmatter, body: "")
    dir = File.join(store, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    fm = frontmatter.map { |k, v| "#{k}: #{v.is_a?(Array) ? "[#{v.join(', ')}]" : v}" }.join("\n")
    File.write(File.join(dir, "#{id}--#{slug}.md"), "---\n#{fm}\n---\n\n## Intent\n#{frontmatter[:intent]}\n#{body}\n")
    dir
  end

  def write_graph(dir, graph_body, node_ids)
    File.write(File.join(dir, "graph.md"), graph_body)
    return if node_ids.empty?

    FileUtils.mkdir_p(File.join(dir, "nodes"))
    node_ids.each do |id|
      File.write(File.join(dir, "nodes", "#{id}.md"), <<~MD)
        ---
        node: #{id}
        kind: work
        files: []
        budget: 1000
        ---
        # #{id}

        ## Steps
        1. go

        ## Proven by
        (later)
      MD
    end
  end

  def build_store
    store = File.join(@home, "projects", "demo", "store")
    FileUtils.mkdir_p(store)
    File.write(File.join(@home, "projects.yml"), "---\nprojects:\n  demo:\n    path: \"/tmp/demo\"\n    status: active\n")
    File.write(File.join(@home, "projects", "demo", "INDEX.md"),
               "# Index\n\n## Active\n\n## Future\n\n- [1 - Graph one](store/1--graph/1--graph.md) - note.\n" \
               "- [2 - Plain one](store/2--plain/2--plain.md) - note.\n\n## Clusters\n\n" \
               "## Abandoned\n\n## Completed\n\n## Relocated\n(none)\n")
    dir1 = write_intent(store, "1", "graph", { id: "1", intent: "Graph one", author: "human", created: "2026-09-01",
                                                tags: [] })
    write_graph(dir1, "## Graph\n- n1 needs nothing\n- n2 needs nothing\n", %w[n1 n2])
    write_intent(store, "2", "plain", { id: "2", intent: "Plain one", author: "human", created: "2026-09-01", tags: [] })
    store
  end

  def next_work_row(out, id)
    data = JSON.parse(out)
    data["next_work"].find { |r| r["id"] == id }
  end

  def test_dashboard_reports_the_ready_node_count_for_a_graph_intent
    build_store
    out, status = run_dash("project", "demo", "--data", "--all")
    assert_equal 0, status
    row = next_work_row(out, "1")
    refute_nil row, "expected intent 1 in next_work"
    assert_equal 2, row["ready_node_count"]
  end

  def test_unblocked_flag_output_is_unchanged
    store = build_store
    # A future intent whose declared source is already delivered, so the
    # pre-existing sources-derived "unblocked" flag fires exactly as before.
    write_intent(store, "3", "waits", { id: "3", intent: "Waits on 1", author: "human", created: "2026-09-08",
                                          sources: ["1"], tags: [] })
    File.write(File.join(File.dirname(store), "INDEX.md"),
               "# Index\n\n## Active\n\n## Future\n\n- [3 - Waits](store/3--waits/3--waits.md) - note.\n" \
               "\n## Clusters\n\n## Abandoned\n\n## Completed\n\n" \
               "- [1 - Graph one](store/1--graph/1--graph.md) - 2026-09-09 note.\n" \
               "## Relocated\n(none)\n")
    out, status = run_dash("project", "demo", "--data", "--all")
    assert_equal 0, status
    row = next_work_row(out, "3")
    refute_nil row
    assert_includes row["flags"], "unblocked"
  end

  def test_ready_set_is_read_only_for_intents_with_a_real_graph
    build_store
    out, status = run_dash("project", "demo", "--data", "--all")
    assert_equal 0, status
    plain_row = next_work_row(out, "2")
    refute_nil plain_row
    assert_nil plain_row["ready_node_count"], "an intent with no graph.md must never be analyzed by ReadySet"
  end
end
