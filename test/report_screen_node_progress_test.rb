# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "open3"
require_relative "../scripts/lib/report_screen"
require_relative "../scripts/lib/intent_screen"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/node_progress"

# Intent 337a, n2: the three screens (state, roster, roadmap entries) ask
# NodeProgress instead of counting checklist.md for a graph-era intent.
# Matrix rows 2.1-2.14 in actions/ACTION_2.md. D7 is the safety net: every
# assertion in report_screen_state_test.rb, report_screen_session_test.rb
# and report_screen_roadmap_test.rb stays untouched by this intent; this
# file proves only the new graph-era path plus the CLI subprocess wiring
# (row 2.13 is those three files staying green, not a test in this one).
class ReportScreenNodeProgressTest < Minitest::Test
  CLI = File.expand_path("../scripts/report-screen", __dir__)

  def setup
    @home = Dir.mktmpdir("report-screen-node-progress")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def tier_root(slug: "demo")
    root = File.join(@home, "projects", slug)
    FileUtils.mkdir_p(File.join(root, "store"))
    root
  end

  def write_index(root, entries)
    sections = { "Active" => [], "Future" => [], "Completed" => [], "Abandoned" => [] }
    entries.each { |id, title, section| sections[section] << "- [#{id} - #{title}](store/#{id}--slug/#{id}--slug.md) - tags\n" }
    body = +"# Index\n\n"
    sections.each { |name, lines| body << "## #{name}\n#{lines.join}\n" }
    File.write(File.join(root, "INDEX.md"), body)
  end

  def intent_md(dir, id, title)
    body = +"---\nid: #{id}\nintent: \"#{title}\"\nsources: []\nchain: []\ncreated: 2026-09-01\nauthor: human\ntags: [demo]\n---\n\n"
    body << "## Intent\n#{title}\n\n## Context\nx\n\n## Outcome\n\n## Insights\n"
    File.write(File.join(dir, "#{id}--slug.md"), body)
  end

  def done_line(subject)
    NodeLedger.transition_line(subject: subject, state: "done", fields: { gates: "green", verdict: "ok" })
  end

  def running_line(subject)
    NodeLedger.transition_line(subject: subject, state: "running",
                                fields: { holder: "auto-a", expires: "2026-09-12T19:00:00Z",
                                          packet: "abc123", model: "sonnet" })
  end

  STAGE_LINE = "2026-09-01T00:00:00Z  Exec  starting work\n"

  def make_checklist_intent(root, id:, title: "Checklist intent", total: 5, done: 2)
    dir = File.join(root, "store", "#{id}--slug")
    FileUtils.mkdir_p(dir)
    intent_md(dir, id, title)
    items = (1..total).map { |n| "- [#{n <= done ? 'x' : ' '}] Step #{n} - do thing #{n}" }
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n## In Progress\n#{items.join("\n")}\n\n## Completed\n\n## Session Log\n")
    File.write(File.join(dir, "savepoint.md"), STAGE_LINE)
    dir
  end

  def make_graph_intent(root, id:, title: "Graph intent", node_ids:, ledger_lines: [], delivered: false, checklist: nil)
    dir = File.join(root, "store", "#{id}--slug")
    nodes_dir = File.join(dir, "nodes")
    FileUtils.mkdir_p(nodes_dir)
    intent_md(dir, id, title)
    lines = node_ids.map { |nid| "- #{nid} needs nothing" }
    File.write(File.join(dir, "graph.md"), "## Graph\n#{lines.join("\n")}\n")
    node_ids.each { |nid| File.write(File.join(nodes_dir, "#{nid}.md"), "# #{nid}\n") }
    File.write(File.join(dir, "savepoint.md"), STAGE_LINE + ledger_lines.join)
    File.write(File.join(dir, "outcome.md"), "## Delivered\n- shipped\n") if delivered
    File.write(File.join(dir, "checklist.md"), checklist) if checklist
    dir
  end

  def progress_row(rows)
    rows.find { |l, _, _| l == "Progress" }
  end

  # --- 2.1 -----------------------------------------------------------------

  def test_state_screen_counts_nodes
    root = tier_root
    node_ids = (1..12).map { |n| "n#{n}" }
    dir = make_graph_intent(root, id: "30", title: "Graph state", node_ids: node_ids,
                             ledger_lines: node_ids.first(6).map { |n| done_line(n) })
    write_index(root, [["30", "Graph state", "Active"]])
    data = ReportScreen.state_fields(intent_dir: dir, store_root: root, changed: nil)
    row = progress_row(data[:rows])
    assert_includes row[1], "6 / 12 nodes"
  end

  # --- 2.2 -----------------------------------------------------------------

  def test_roster_counts_nodes
    root = tier_root
    node_ids = (1..12).map { |n| "n#{n}" }
    make_graph_intent(root, id: "31", title: "Graph roster", node_ids: node_ids,
                       ledger_lines: node_ids.first(6).map { |n| done_line(n) })
    write_index(root, [["31", "Graph roster", "Active"]])
    out = ReportScreen.render_roster(root)
    row = out.lines.find { |l| l.start_with?("| 31 |") }
    refute_nil row, "no roster row for 31 in:\n#{out}"
    assert_includes row, "6 / 12 nodes"
  end

  # --- 2.3 -----------------------------------------------------------------

  def test_roadmap_entry_counts_nodes
    root = tier_root(slug: "roadmap")
    node_ids = (1..12).map { |n| "n#{n}" }
    dir = make_graph_intent(root, id: "32", title: "Graph roadmap", node_ids: node_ids,
                             ledger_lines: node_ids.first(6).map { |n| done_line(n) })
    assert_equal "6 / 12 nodes", ReportScreen.roadmap_entry_progress(dir).sub(/\A\S+\s+/, "")
  end

  # --- 2.4 -----------------------------------------------------------------

  def test_graph_era_figure_is_labelled_nodes
    root = tier_root
    node_ids = %w[n1 n2 n3]
    dir = make_graph_intent(root, id: "33", title: "Graph label", node_ids: node_ids,
                             ledger_lines: [done_line("n1")])
    write_index(root, [["33", "Graph label", "Active"]])
    data = ReportScreen.state_fields(intent_dir: dir, store_root: root, changed: nil)
    assert_match(/\A\S+ 1 \/ 3 nodes\z/, progress_row(data[:rows])[1])

    out = ReportScreen.render_roster(root)
    row = out.lines.find { |l| l.start_with?("| 33 |") }
    assert_includes row, "1 / 3 nodes"

    assert_match(/\A\S+ 1 \/ 3 nodes\z/, ReportScreen.roadmap_entry_progress(dir))
  end

  # --- 2.5 -----------------------------------------------------------------

  def test_checklist_era_figures_are_unchanged
    root = tier_root
    dir = make_checklist_intent(root, id: "34", title: "Checklist unchanged", total: 5, done: 2)
    write_index(root, [["34", "Checklist unchanged", "Active"]])

    items = IntentScreen.checklist_items(dir)
    expected = IntentScreen.progress_fields(items)
    expected_value = "#{expected['progress.bar']} #{expected['progress.done']} / #{expected['progress.total']}"

    data = ReportScreen.state_fields(intent_dir: dir, store_root: root, changed: nil)
    assert_equal expected_value, progress_row(data[:rows])[1]
    refute_match(/nodes/, progress_row(data[:rows])[1])

    out = ReportScreen.render_roster(root)
    row = out.lines.find { |l| l.start_with?("| 34 |") }
    assert_includes row, expected_value
    refute_match(/nodes/, row)

    assert_equal expected_value, ReportScreen.roadmap_entry_progress(dir)
  end

  # --- 2.6 -----------------------------------------------------------------

  def test_running_nodes_show_in_the_note
    root = tier_root
    node_ids = %w[n1 n2 n3 n4 n5]
    dir = make_graph_intent(root, id: "35", title: "Graph running", node_ids: node_ids,
                             ledger_lines: [done_line("n1"), running_line("n2")])
    write_index(root, [["35", "Graph running", "Active"]])
    data = ReportScreen.state_fields(intent_dir: dir, store_root: root, changed: nil)
    row = progress_row(data[:rows])
    assert_equal "4 nodes open, 1 running", row[2]
  end

  # --- 2.7 -----------------------------------------------------------------

  def test_inferred_intent_says_inferred
    root = tier_root
    node_ids = %w[n1 n2]
    dir = make_graph_intent(root, id: "36", title: "Graph inferred", node_ids: node_ids,
                             ledger_lines: [], delivered: true)
    write_index(root, [["36", "Graph inferred", "Completed"]])
    data = ReportScreen.state_fields(intent_dir: dir, store_root: root, changed: nil)
    row = progress_row(data[:rows])
    assert_includes row[1], "2 / 2 nodes"
    assert_equal "inferred: delivered before the node ledger", row[2]
  end

  # --- 2.8 -----------------------------------------------------------------

  def test_next_row_still_reads_the_checklist
    root = tier_root
    node_ids = %w[n1 n2]
    checklist = "# Checklist\n\n## In Progress\n- [ ] Step 1 - write the migration\n\n## Completed\n\n## Session Log\n"
    dir = make_graph_intent(root, id: "37", title: "Graph next", node_ids: node_ids,
                             ledger_lines: [done_line("n1")], checklist: checklist)
    write_index(root, [["37", "Graph next", "Active"]])
    data = ReportScreen.state_fields(intent_dir: dir, store_root: root, changed: nil)
    next_row = data[:rows].find { |l, _, _| l == "Next" }
    assert_includes next_row[1], "write the migration"
    refute_includes next_row[1], "n1"
    refute_includes next_row[1], "n2"
  end

  # --- 2.9 -------------------------------------------------------------------

  def test_subprocess_state_graph_era
    root = tier_root
    node_ids = (1..12).map { |n| "n#{n}" }
    dir = make_graph_intent(root, id: "38", title: "Graph subprocess", node_ids: node_ids,
                             ledger_lines: node_ids.first(6).map { |n| done_line(n) })
    write_index(root, [["38", "Graph subprocess", "Active"]])
    out, err, status = Open3.capture3("ruby", CLI, "state", dir)
    assert_equal 0, status.exitstatus, err
    assert_includes out, "6 / 12 nodes"
  end

  # --- 2.10 --------------------------------------------------------------------

  def test_subprocess_roster_both_kinds
    root = tier_root
    node_ids = (1..4).map { |n| "n#{n}" }
    make_graph_intent(root, id: "39", title: "Graph both", node_ids: node_ids,
                       ledger_lines: [done_line("n1"), done_line("n2")])
    make_checklist_intent(root, id: "40", title: "Checklist both", total: 4, done: 1)
    write_index(root, [["39", "Graph both", "Active"], ["40", "Checklist both", "Active"]])
    out, err, status = Open3.capture3("ruby", CLI, "state", "--all", root)
    assert_equal 0, status.exitstatus, err
    row39 = out.lines.find { |l| l.start_with?("| 39 |") }
    row40 = out.lines.find { |l| l.start_with?("| 40 |") }
    assert_includes row39, "2 / 4 nodes"
    assert_includes row40, "1 / 4"
    refute_match(/nodes/, row40)
  end

  # --- 2.11 --------------------------------------------------------------------

  def test_subprocess_roadmap_both_kinds
    node_ids = (1..4).map { |n| "n#{n}" }
    make_graph_intent(@home, id: "41", title: "Graph roadmap sub", node_ids: node_ids,
                       ledger_lines: [done_line("n1")])
    make_checklist_intent(@home, id: "42", title: "Checklist roadmap sub", total: 4, done: 3)
    lines = ["# Index", "", "## Active", "",
             "- [41 - Graph roadmap sub](store/41--slug/41--slug.md) - tags",
             "- [42 - Checklist roadmap sub](store/42--slug/42--slug.md) - tags",
             "", "## Future", "", "## Completed", "", "## Abandoned", ""]
    File.write(File.join(@home, "INDEX.md"), lines.join("\n") + "\n")
    roadmap_path = File.join(@home, "roadmap.md")
    File.write(roadmap_path, <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 41 Graph roadmap sub - queued
      - [ ] 42 Checklist roadmap sub - queued
      ## Log
    MD
    out, err, status = Open3.capture3("ruby", CLI, "roadmap", roadmap_path, "state", "--store-root", @home)
    assert_equal 0, status.exitstatus, err
    row41 = out.lines.find { |l| l.include?("| 41 |") }
    row42 = out.lines.find { |l| l.include?("| 42 |") }
    assert_includes row41, "1 / 4 nodes"
    assert_includes row42, "3 / 4"
    refute_match(/nodes/, row42)
  end

  # --- 2.12 --------------------------------------------------------------------

  def test_unresolvable_entry_still_renders_not_recorded
    assert_equal "not recorded", ReportScreen.roadmap_entry_progress(nil)
  end
end
