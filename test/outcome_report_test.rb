# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "timeout"
require_relative "../scripts/lib/outcome_report"
require_relative "../scripts/lib/report_screen"
require_relative "../scripts/lib/savepoint"

# OutcomeReport (intent 339, G6): the report model over graph.md, nodes/, and
# the node ledger (n1), the generator and its command (n2), the plan-versus-
# delivered diff and stale computation (n3), and findings (n4). Every rendered
# cell traces to graph.md, a node file, or a ledger line; an absent source
# renders as the named reason, never a guess (spec D1).
class OutcomeReportTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("outcome-report")
    @dir = File.join(@root, "12--slug")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(rel, body)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def write_graph(graph_body)
    write("graph.md", <<~MD)
      # Graph: Test

      ## Goal
      Test goal.

      ## Decisions
      - D1 test

      ## Graph
      #{graph_body}

      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  def write_node(id, kind: "work", title: nil, body_extra: "")
    heading = title ? "# #{id} - #{title}" : "(no title heading)"
    write("nodes/#{id}.md", <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: []
      budget: 1000
      ---
      #{heading}

      #{body_extra}
    MD
  end

  def write_ledger(lines)
    write("savepoint.md", lines.join)
  end

  # --- 1.1 -----------------------------------------------------------------

  def test_malformed_graph_returns_errors_not_raise
    write_graph("- n1 needs\n")
    model = OutcomeReport.model(@dir)
    refute model[:ok]
    refute_empty model[:errors]
  end

  # --- 1.2 -----------------------------------------------------------------

  def test_missing_title_falls_back_to_node_id
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: nil)
    model = OutcomeReport.model(@dir)
    assert_equal "n1", model[:nodes]["n1"][:title]
  end

  # --- 1.3 -----------------------------------------------------------------

  def test_node_without_ledger_line_reads_planned
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    model = OutcomeReport.model(@dir)
    assert_equal "planned", model[:nodes]["n1"][:state]
  end

  # --- 1.4 -----------------------------------------------------------------

  def test_evidence_comes_from_last_done_line
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_ledger([
      "2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n",
      "2026-09-09T10:05:00Z  n1  failed_verification gates=tests reason=broke\n",
      "2026-09-09T10:10:00Z  n1  done gates=tests commit=bbb2222\n",
    ])
    model = OutcomeReport.model(@dir)
    assert_equal "bbb2222", model[:nodes]["n1"][:fields]["commit"]
  end

  # --- 1.5 -----------------------------------------------------------------

  def test_retry_count_from_failed_verification_lines
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_ledger([
      "2026-09-09T10:00:00Z  n1  running holder=h expires=2026-09-09T11:00:00Z packet=A model=sonnet\n",
      "2026-09-09T10:01:00Z  n1  failed_verification gates=tests reason=broke\n",
      "2026-09-09T10:02:00Z  n1  running holder=h expires=2026-09-09T11:00:00Z packet=A model=sonnet\n",
      "2026-09-09T10:03:00Z  n1  failed_verification gates=tests reason=broke\n",
      "2026-09-09T10:04:00Z  n1  running holder=h expires=2026-09-09T11:00:00Z packet=A model=sonnet\n",
      "2026-09-09T10:05:00Z  n1  done gates=tests commit=ccc3333\n",
    ])
    model = OutcomeReport.model(@dir)
    assert_equal 2, model[:nodes]["n1"][:retries]
  end

  # --- 1.6 -----------------------------------------------------------------

  def test_absent_graph_returns_named_reason
    model = OutcomeReport.model(@dir)
    refute model[:ok]
    assert(model[:errors].any? { |e| e.include?("graph.md") })
    assert_equal({}, model[:nodes])
  end

  # --- 1.7 -----------------------------------------------------------------

  def test_undeclared_node_file_is_recorded
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_node("n9", title: "Undeclared")
    model = OutcomeReport.model(@dir)
    refute model[:nodes]["n9"][:declared]
  end

  # --- 1.8 -----------------------------------------------------------------

  def test_declared_node_without_file_still_listed
    write_graph("- n1 needs nothing\n- n3 needs n1\n")
    write_node("n1", title: "Title")
    model = OutcomeReport.model(@dir)
    entry = model[:nodes]["n3"]
    refute_nil entry
    assert entry[:declared]
    refute entry[:file_present]
    assert_equal "work", entry[:kind]
    assert_equal "n3", entry[:title]
  end

  # --- 1.9 -----------------------------------------------------------------

  def test_torn_line_excluded_from_state
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_ledger([
      "2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n",
      "2026-09-09T10:05:00Z  n1  running holder=h\n", # torn: missing expires/packet/model
    ])
    model = OutcomeReport.model(@dir)
    assert_equal "done", model[:nodes]["n1"][:state]
  end

  # --- 1.10 ----------------------------------------------------------------

  def test_invalid_utf8_byte_does_not_raise
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    bad = "2026-09-09T10:00:00Z  n1  done gates=tests commit=\xFF\xFEbad\n".dup.force_encoding("UTF-8")
    write("savepoint.md", bad)
    model = OutcomeReport.model(@dir)
    refute_nil model
  end

  # --- v1f.4 (N4) --------------------------------------------------------------

  def test_model_rescues_a_raising_reader
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    model = OutcomeReport.model(@dir, node_file_parser: ->(*) { raise "boom" })
    refute model[:ok]
    assert(model[:errors].any? { |e| e.include?("boom") })
  end

  # --- 1.11 ------------------------------------------------------------------

  def test_library_source_reads_no_clock_or_environment
    source = File.read(File.join(__dir__, "..", "scripts", "lib", "outcome_report.rb"))
    refute_match(/\bTime\./, source)
    refute_match(/ENV\[/, source)
  end

  # --- 1.12 --------------------------------------------------------------------

  def test_model_does_not_call_needs_from_graph
    source = File.read(File.join(__dir__, "..", "scripts", "lib", "outcome_report.rb"))
    refute_includes source, "needs_from_graph"
  end

  # --- n2 helpers ------------------------------------------------------------

  def build_model(nodes: {}, edges: {}, goal: "Test goal.")
    { ok: true, errors: [], goal: goal, edges: edges, nodes: nodes }
  end

  def a_node(kind: "work", state: "done", title: "Title", fields: {}, failure_fields: {}, retries: 0,
             declared: true, file_present: true)
    { declared: declared, file_present: file_present, kind: kind, title: title,
      state: state, fields: fields, failure_fields: failure_fields, retries: retries }
  end

  # --- 2.1 -------------------------------------------------------------------

  def test_frontmatter_carries_requested_disposition
    text = OutcomeReport.render(build_model, disposition: "delivered")
    assert_match(/\Adisposition: delivered/, text.split("---")[1].to_s.strip)
  end

  # --- 2.2 -------------------------------------------------------------------

  def test_authored_summary_preserved_byte_for_byte
    existing = "---\ndisposition: delivered\n---\n# Outcome: x\n\n## Summary\nMy authored words survive.\n\n## Delivered\n| Row | What |\n| --- | --- |\n"
    text = OutcomeReport.render(build_model, disposition: "delivered", existing: existing)
    assert_includes text, "My authored words survive."
  end

  # --- 2.3 -------------------------------------------------------------------

  def test_placeholder_summary_replaced_with_facts
    existing = "---\ndisposition: delivered\n---\n# Outcome: x\n\n## Summary\n(what was delivered)\n\n## Delivered\n| Row | What |\n| --- | --- |\n"
    text = OutcomeReport.render(build_model(nodes: { "n1" => a_node }), disposition: "delivered", existing: existing)
    refute_includes text, "(what was delivered)"
    assert_match(/\d+ of \d+ work node/, text)
  end

  # --- 2.4 -------------------------------------------------------------------

  def test_delivered_rows_are_done_work_nodes_labeled_by_id
    model = build_model(nodes: { "n1" => a_node(title: "Alpha thing") })
    text = OutcomeReport.render(model, disposition: "delivered")
    assert_includes text, "| n1 | Alpha thing |"
  end

  # --- 2.5 -------------------------------------------------------------------

  def test_non_work_nodes_are_not_delivered_rows
    model = build_model(nodes: { "v1" => a_node(kind: "verify", title: "Review") })
    text = OutcomeReport.render(model, disposition: "delivered")
    refute_includes text, "| v1 |"
  end

  # --- 2.6 -------------------------------------------------------------------

  def test_no_done_work_nodes_renders_honest_delivered_section
    model = build_model(nodes: { "n1" => a_node(state: "planned") })
    text = OutcomeReport.render(model, disposition: "delivered")
    assert_includes text, "## Delivered"
    delivered = text.split("## Delivered", 2)[1].split("## ", 2)[0]
    refute_match(/\|\s*n1\s*\|/, delivered)
  end

  # --- 2.7 -------------------------------------------------------------------

  def test_verification_lines_come_from_ledger_fields
    model = build_model(nodes: { "n1" => a_node(fields: { "gates" => "tests", "commit" => "abc1234" }) })
    text = OutcomeReport.render(model, disposition: "delivered")
    verification = text.split("## Verification", 2)[1].to_s
    assert_includes verification, "abc1234"
    assert_includes verification, "tests"
  end

  # --- v1f.14 (dogfood) --------------------------------------------------------

  def test_failed_verification_line_cites_the_ledger_reason
    # `node_entry` fills `fields` from the last DONE line only (row 1.4); a
    # failed_verification node has no done line, so `fields` stays {} and
    # `verification_line_for`'s old `fields['reason']` lookup could never
    # succeed. The reason lives in a SEPARATE ledger line and must be read
    # from there (this intent's own dogfood: v1's own record hit this).
    write_graph("- v1 needs nothing\n")
    write_node("v1", kind: "verify", title: "Review")
    write_ledger([
      "2026-09-09T10:00:00Z  v1  running holder=h expires=2026-09-09T11:00:00Z packet=A model=sonnet\n",
      "2026-09-09T10:05:00Z  v1  failed_verification gates=tests reason=\"3 blocking: row 7.2 tautology hides the guard\"\n",
    ])
    model = OutcomeReport.model(@dir)
    text = OutcomeReport.render(model, disposition: "delivered")
    verification = text.split("## Verification", 2)[1].to_s
    assert_includes verification, "3 blocking: row 7.2 tautology hides the guard"
    refute_includes verification, "reason not recorded"
  end

  # --- 2.8 -------------------------------------------------------------------

  def test_generated_verification_yields_evidence_rows
    model = build_model(nodes: { "n1" => a_node(fields: { "gates" => "tests", "commit" => "abc1234" }) })
    text = OutcomeReport.render(model, disposition: "delivered")
    write("outcome.md", text)
    write("12--slug.md", "---\nid: \"12\"\nintent: \"x\"\n---\n\n## Intent\nx\n")
    refute_empty ReportScreen.evidence_rows(@dir)
  end

  # --- 2.9 -------------------------------------------------------------------

  def test_pipe_in_title_reads_back_whole_through_delivered_rows
    model = build_model(nodes: { "n1" => a_node(title: "A | B thing") })
    text = OutcomeReport.render(model, disposition: "delivered")
    write("outcome.md", text)
    write("12--slug.md", "---\nid: \"12\"\nintent: \"x\"\n---\n\n## Intent\nx\n")
    rows = ReportScreen.delivered_rows(@dir)
    row = rows.find { |r| r[:label] == "n1" }
    refute_nil row
    assert_equal "A / B thing", row[:text]
  end

  # --- 2.10 --------------------------------------------------------------------

  def test_authored_needs_you_and_followups_preserved
    existing = <<~MD
      ---
      disposition: delivered
      ---
      # Outcome: x

      ## Summary
      x

      ## Delivered
      | Row | What |
      | --- | --- |

      ## Needs you
      | N | Need | Reason |
      | --- | --- | --- |
      | N1 | Pick a color | because reasons |

      ## Follow-ups
      | N | What | Why |
      | --- | --- | --- |
      | 1 | Do a thing | because reasons |
    MD
    text = OutcomeReport.render(build_model, disposition: "delivered", existing: existing)
    assert_includes text, "Pick a color"
    assert_includes text, "Do a thing"
  end

  # --- 2.11 --------------------------------------------------------------------

  def test_regeneration_preserves_mode_frontmatter
    existing = "---\ndisposition: delivered\nmode: auto\n---\n# Outcome: x\n\n## Summary\nx\n"
    text = OutcomeReport.render(build_model, disposition: "delivered", existing: existing)
    assert_match(/^mode: auto$/, text.split("---")[1].to_s)
  end

  # --- 2.12 --------------------------------------------------------------------

  def test_needs_decision_nodes_render_as_needs_you_rows
    model = build_model(nodes: { "n1" => a_node(state: "needs_decision", fields: { "question" => "Which color?" }) })
    text = OutcomeReport.render(model, disposition: "delivered")
    needs = text.split("## Needs you", 2)[1].to_s
    assert_includes needs, "Which color?"
  end

  # --- 2.13 --------------------------------------------------------------------

  def test_write_goes_through_atomic_write
    write_graph("- n1 needs nothing\n")
    write_node("n1", title: "Title")
    write_ledger(["2026-09-09T10:00:00Z  n1  done gates=tests commit=abc1234\n"])
    called = false
    OutcomeReport.write(@dir, disposition: "delivered", renamer: lambda { |temp, target|
      called = true
      File.rename(temp, target)
    })
    assert called
    assert File.exist?(File.join(@dir, "outcome.md"))
  end

  # --- v1f.3 (B3) --------------------------------------------------------------

  def test_frontmatter_value_with_colon_round_trips
    existing = "---\ndisposition: delivered\nnote: \"a value: with a colon\"\n---\n# Outcome: x\n\n## Summary\nx\n"
    text = OutcomeReport.render(build_model, disposition: "delivered", existing: existing)
    fm_block = text.split("---", 3)[1].to_s
    parsed = YAML.safe_load(fm_block, permitted_classes: [Date, Time])
    refute_nil parsed
    assert_equal "a value: with a colon", parsed["note"]
    assert_equal "delivered", parsed["disposition"]
  end

  # --- v1f.11 (N10) --------------------------------------------------------------

  def test_title_is_a_sentence_not_a_wrapped_line
    goal = "This is a goal sentence that is intentionally long enough to wrap\nacross two lines in the source file."
    model = build_model(goal: goal)
    title = OutcomeReport.title_text(model)
    assert_includes title, "wrap across two lines in the source file."
    refute_includes title, "\n"
  end

  # --- n3: plan versus delivered, and stale -----------------------------------

  def ledger_entries
    NodeLedger.entries(File.join(@dir, "savepoint.md"))
  end

  # --- 3.1 -----------------------------------------------------------------

  def test_diff_names_planned_node_not_done
    model = build_model(nodes: { "n1" => a_node(state: "planned") })
    model[:entries] = []
    diff = OutcomeReport.graph_diff(model)
    assert_includes diff, "n1 is planned, not done"
  end

  # --- 3.2 -----------------------------------------------------------------

  def test_diff_names_undeclared_node
    model = build_model(nodes: { "n9" => a_node(state: "done", declared: false) })
    model[:entries] = []
    diff = OutcomeReport.graph_diff(model)
    assert_includes diff, "n9 was not declared in graph.md"
  end

  # --- 3.3 -----------------------------------------------------------------

  def test_diff_names_retried_node_with_count
    model = build_model(nodes: { "n1" => a_node(state: "done", retries: 2) })
    model[:entries] = []
    diff = OutcomeReport.graph_diff(model)
    assert_includes diff, "n1 took 2 retries"
  end

  # --- 3.4 -----------------------------------------------------------------

  def test_diff_marks_stale_node
    write_ledger([
      "2026-09-09T10:00:00Z  n2  done gates=tests commit=aaa1111\n",
      "2026-09-09T10:01:00Z  n1  superseded by=n1b\n",
    ])
    model = build_model(nodes: { "n1" => a_node(state: "superseded"), "n2" => a_node(state: "done") },
                         edges: { "n2" => ["n1"] })
    model[:entries] = ledger_entries
    diff = OutcomeReport.graph_diff(model)
    assert_includes diff, "n2 is stale"
  end

  # --- 3.5 -----------------------------------------------------------------

  def test_diff_with_no_divergence_renders_one_line
    model = build_model(nodes: { "n1" => a_node(state: "done") })
    model[:entries] = []
    diff = OutcomeReport.graph_diff(model)
    assert_includes diff, "Delivered matches the plan."
  end

  # --- 3.6 -----------------------------------------------------------------

  def test_stale_uses_line_position_not_timestamp
    write_ledger([
      "2026-09-09T12:00:00Z  n2  done gates=tests commit=aaa1111\n",
      "2026-09-09T08:00:00Z  n1  superseded by=n1b\n",
    ])
    stale = OutcomeReport.stale_nodes(entries: ledger_entries, edges: { "n2" => ["n1"] })
    assert_includes stale, "n2"
  end

  # --- 3.7 -----------------------------------------------------------------

  def test_stale_is_transitive_over_the_needs_closure
    write_ledger([
      "2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n",
      "2026-09-09T10:01:00Z  n3  superseded by=n3b\n",
    ])
    stale = OutcomeReport.stale_nodes(entries: ledger_entries, edges: { "n1" => ["n2"], "n2" => ["n3"] })
    assert_includes stale, "n1"
  end

  # --- 3.8 -----------------------------------------------------------------

  def test_cyclic_graph_reports_rather_than_loops
    write_ledger(["2026-09-09T10:00:00Z  n1  done gates=tests commit=aaa1111\n"])
    stale = nil
    assert_equal 1, Timeout.timeout(5) { stale = OutcomeReport.stale_nodes(entries: ledger_entries, edges: { "n1" => ["n2"], "n2" => ["n1"] }); 1 }
    assert_equal [], stale
  end

  # --- 3.9 -----------------------------------------------------------------

  def test_superseded_then_reinstated_is_not_stale
    write_ledger([
      "2026-09-09T10:00:00Z  n2  done gates=tests commit=aaa1111\n",
      "2026-09-09T10:01:00Z  n1  superseded by=n1b\n",
      "2026-09-09T10:02:00Z  n1  running holder=h expires=2026-09-09T11:00:00Z packet=A model=sonnet\n",
    ])
    stale = OutcomeReport.stale_nodes(entries: ledger_entries, edges: { "n2" => ["n1"] })
    refute_includes stale, "n2"
  end

  # --- 3.10 --------------------------------------------------------------------

  def test_supersession_before_done_is_not_stale
    write_ledger([
      "2026-09-09T10:00:00Z  n1  superseded by=n1b\n",
      "2026-09-09T10:01:00Z  n2  done gates=tests commit=aaa1111\n",
    ])
    stale = OutcomeReport.stale_nodes(entries: ledger_entries, edges: { "n2" => ["n1"] })
    refute_includes stale, "n2"
  end

  # --- 3.11 --------------------------------------------------------------------

  def test_stale_unchanged_across_rebuild_savepoint
    write("12--slug.md", "---\nid: \"12\"\nintent: \"x\"\n---\n\n## Intent\nx\n")
    write_ledger([
      "2026-09-09T10:00:00Z  n2  done gates=tests commit=aaa1111\n",
      "2026-09-09T10:01:00Z  n1  superseded by=n1b\n",
    ])
    edges = { "n2" => ["n1"] }
    before = OutcomeReport.stale_nodes(entries: ledger_entries, edges: edges)
    Savepoint.rebuild_savepoint(@dir)
    after = OutcomeReport.stale_nodes(entries: ledger_entries, edges: edges)
    assert_equal before, after
  end

  # --- 3.12 --------------------------------------------------------------------

  def test_stale_fn_seam_is_injectable
    stub = ->(entries:, edges:) { ["n7"] }
    result = OutcomeReport.stale_nodes(entries: [], edges: {}, stale_fn: stub)
    assert_equal ["n7"], result
  end

  # --- n4: findings, read and capped ------------------------------------------

  def write_intent_file(insights_body)
    write("12--slug.md", <<~MD)
      ---
      id: "12"
      intent: "x"
      ---

      ## Intent
      x

      ## Insights
      #{insights_body}
    MD
  end

  # --- 4.1 -----------------------------------------------------------------

  def test_findings_read_from_insights_subsection
    write_intent_file(<<~MD)
      2026-09-09T10:00:00Z · Exec · someone (autonomous) - some insight

      ### Findings
      - Finding one
      - Finding two
    MD
    assert_equal ["Finding one", "Finding two"], OutcomeReport.findings(@dir)
  end

  # --- 4.2 -----------------------------------------------------------------

  def test_finding_over_cap_is_truncated_with_ellipsis
    long_text = "a" * 250
    write_intent_file(<<~MD)
      ### Findings
      - #{long_text}
    MD
    result = OutcomeReport.findings(@dir).first
    assert_operator result.length, :<=, OutcomeReport::FINDING_CAP
    assert result.end_with?("..."), "expected #{result.inspect} to end with an ellipsis"
  end

  # --- 4.3 -----------------------------------------------------------------

  def test_no_findings_omits_the_section
    write_intent_file(<<~MD)
      2026-09-09T10:00:00Z · Exec · someone (autonomous) - some insight
    MD
    assert_equal [], OutcomeReport.findings(@dir)
    text = OutcomeReport.render(build_model, disposition: "delivered", findings: OutcomeReport.findings(@dir))
    refute_includes text, "## Findings"
  end

  # --- 4.4 -----------------------------------------------------------------

  def test_pipe_in_finding_reads_back_whole
    write_intent_file(<<~MD)
      ### Findings
      - A finding | with a pipe in it
    MD
    findings = OutcomeReport.findings(@dir)
    text = OutcomeReport.render(build_model, disposition: "delivered", findings: findings)
    write("outcome.md", text)
    rows = ReportScreen.table_rows(ReportScreen.section_of(File.read(File.join(@dir, "outcome.md")), "## Findings"))
    assert_equal "A finding / with a pipe in it", rows.first[0]
  end

  # --- 4.5 -----------------------------------------------------------------

  def test_insights_without_findings_subsection_returns_empty
    # A bulleted Insights fixture (post-execution review N5): a fallback that
    # returns the whole "## Insights" body as one finding stays green against
    # a non-bullet fixture, since finding_bullet_rows finds no bullet to
    # return. Real records carry bullet-shaped Insights lines, so this
    # fixture must too.
    write_intent_file(<<~MD)
      - 2026-09-09T10:00:00Z · Exec · someone (autonomous) - an insight with no findings subsection
    MD
    assert_equal [], OutcomeReport.findings(@dir)
  end

  # --- 10.1 --------------------------------------------------------------------

  # D19: a delivered row is labelled by the S-label of the action heading that
  # owns the node's matrix. Today `render_delivered_section` has no way to
  # consult `intent_dir` at all - it always emits the bare node id - so the
  # generator's own output cannot close under an already-installed core that
  # only knows S-labels.
  def test_delivered_row_label_prefers_the_action_s_label
    write("actions/ACTION_1.md", <<~MD)
      ### S10 - n9 - A delivered row carries the label its action heading owns

      | Row | Operation | Failure mode | Test |
      | --- | --- | --- | --- |
      | 10.1 | a | b | c |
    MD
    model = build_model(nodes: { "n9" => a_node(title: "Ninth thing") })
    text = OutcomeReport.render_delivered_section(model, intent_dir: @dir)
    assert_includes text, "| S10 | Ninth thing |"
  end

  # --- 10.2 --------------------------------------------------------------------

  def test_delivered_row_label_falls_back_to_node_id
    write("actions/ACTION_1.md", <<~MD)
      ### n9 - A delivered row carries the label its action heading owns

      | Row | Operation | Failure mode | Test |
      | --- | --- | --- | --- |
      | 9.1 | a | b | c |
    MD
    model = build_model(nodes: { "n9" => a_node(title: "Ninth thing") })
    text = OutcomeReport.render_delivered_section(model, intent_dir: @dir)
    assert_includes text, "| n9 | Ninth thing |"
  end

  # --- 10.3 --------------------------------------------------------------------

  def test_emitted_label_resolves_through_proven_by
    write("actions/ACTION_1.md", <<~MD)
      ### S10 - n9 - A delivered row carries the label its action heading owns

      | Row | Operation | Failure mode | Test |
      | --- | --- | --- | --- |
      | 10.1 | a | b | c |
      | 10.2 | d | e | f |
    MD
    model = build_model(nodes: { "n9" => a_node(title: "Ninth thing") })
    text = OutcomeReport.render_delivered_section(model, intent_dir: @dir)
    emitted_label = text[/\|\s*(\S+)\s*\|\s*Ninth thing\s*\|/, 1]
    assert_equal "S10", emitted_label
    assert_equal "2 tests", ReportScreen.proven_by(@dir, emitted_label)
  end
end
