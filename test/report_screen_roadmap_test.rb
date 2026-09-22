# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require "json"
require_relative "../scripts/lib/report_screen"
require_relative "../scripts/lib/roadmap_queue"
require_relative "../scripts/lib/roadmap_savepoint"
require_relative "../scripts/lib/lock"

# Intent 331c: report-screen roadmap <roadmap.md> plan|state|delivered, the roadmap's own three
# reports (D1-D7). Hermetic tmpdir fixtures shaped like the real roadmaps (reporting-v2.md's
# Batches, manual-first.md's legacy Waves with no ledger file), never the live files under
# ~/.plastic/projects/plastic/roadmaps/.
class ReportScreenRoadmapTest < Minitest::Test
  NOW = Time.utc(2026, 9, 5, 12, 0, 0)

  def setup
    @home = Dir.mktmpdir("report-screen-roadmap")
    @roadmaps = File.join(@home, "roadmaps")
    FileUtils.mkdir_p(@roadmaps)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def roadmap_path(slug)
    File.join(@roadmaps, "#{slug}.md")
  end

  def write_roadmap(slug, body)
    path = roadmap_path(slug)
    File.write(path, body)
    path
  end

  def write_ledger(slug, lines)
    File.write(File.join(@roadmaps, "#{slug}.savepoint.md"), lines.map { |l| "#{l}\n" }.join)
  end

  def index_line(id, title: "Title")
    "- [#{id} — #{title}](store/#{id}--slug/#{id}--slug.md) — 2026-07-10 note."
  end

  def write_index(active: [], future: [], completed: [], abandoned: [])
    lines = ["# Index", "", "## Active", ""]
    active.each { |id| lines << index_line(id) }
    lines += ["", "## Future", ""]
    future.each { |id| lines << index_line(id) }
    lines += ["", "## Clusters", "", "## Abandoned", ""]
    abandoned.each { |id| lines << index_line(id) }
    lines += ["", "## Completed", ""]
    completed.each { |id| lines << index_line(id) }
    File.write(File.join(@home, "INDEX.md"), lines.join("\n") + "\n")
  end

  def make_entry_dir(id, done: 0, total: 0)
    dir = File.join(@home, "store", "#{id}--slug")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--slug.md"), "---\nid: \"#{id}\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
    lines = (1..total).map { |i| "- [#{i <= done ? 'x' : ' '}] S#{i} step #{i}\n" }
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n#{lines.join}")
    dir
  end

  def write_lock(dir, owner_agent: "plastic-enforcer", owner_session: "sess1234", mtime: nil)
    path = File.join(dir, "delivery.lock")
    File.write(path, { "owner_agent" => owner_agent, "owner_session" => owner_session }.to_json)
    File.utime(mtime, mtime, path) if mtime
    path
  end

  def render(path, verb, store_root: @home, now: NOW, template: nil)
    ReportScreen.render_roadmap(path: path, verb: verb, store_root: store_root, now: now, template: template)
  end

  # --- R1: entries come from RoadmapQueue, never a second parser --------------------

  def test_entries_come_from_roadmap_queue
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 901 Solo title - queued
      ## Log
    MD
    write_index

    data = ReportScreen.roadmap_entries(path: roadmap_path("demo"), store_root: @home)
    entry = data[:batches].first[:entries].first
    assert_equal "901", entry[:id]
    assert_equal "Solo title", entry[:text]
    assert_equal "queued", entry[:status]
  end

  # --- R2: INDEX wins over the roadmap file's own token ------------------------------

  def test_index_status_overrides_file_token
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 301 Solo — queued
      ## Log
    MD
    write_index(completed: %w[301])

    out = render(roadmap_path("demo"), "plan")
    row = out.lines.find { |l| l.include?("| 301 |") }
    assert_includes row, "| delivered |"
    refute_includes row, "| queued |"
  end

  # --- R3: legacy Waves roadmap still renders, with a Wave column header ------------

  def test_waves_roadmap_renders_with_wave_labels
    write_roadmap("legacy", <<~MD)
      # Roadmap: Legacy
      ## Goal
      test.
      ## Waves
      ### Wave 1
      - [x] 158a Group-first skill renames — delivered
      ## Log
    MD
    write_index(completed: %w[158a])

    out = render(roadmap_path("legacy"), "plan")
    assert_includes out, "| Wave | Graph ID | Intent | Status |"
    assert_includes out, "| Wave 1 | 158a | Group-first skill renames | delivered |"
    refute_includes out, "| Batch | Graph ID | Intent | Status |"
  end

  # --- R4: plan Goal is the first sentence, never the whole paragraph ---------------

  def test_plan_goal_is_first_sentence
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      First sentence ends here. Second sentence must not appear on the screen at all.
      ## Batches
      ### Batch 1
      - [ ] 401 Solo — queued
      ## Log
    MD
    write_index

    out = render(roadmap_path("demo"), "plan")
    assert_includes out, "First sentence ends here."
    refute_includes out, "Second sentence must not appear"
  end

  # --- R5: plan Created is not recorded when there is no ledger and no Log ----------

  def test_plan_created_not_recorded_without_ledger
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 401 Solo — queued
    MD
    write_index

    out = render(roadmap_path("demo"), "plan")
    row = out.lines.find { |l| l.start_with?("| **Created**") }
    assert_includes row, "not recorded"
  end

  # --- R6: state Progress counts intents, never batches -----------------------------

  def test_state_progress_counts_intents
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [x] 501 Alpha — delivered
      - [x] 502 Beta — delivered
      - [ ] 503 Gamma — queued
      - [ ] 504 Delta — queued
      ## Log
    MD
    write_index(completed: %w[501 502], future: %w[503 504])

    out = render(roadmap_path("demo"), "state")
    row = out.lines.find { |l| l.start_with?("| **Progress**") }
    assert_includes row, "2 / 4"
    refute_includes row, "1 / 1", "one batch must never be reported as the total"
  end

  # --- R7/D6: state Delivering never shows a dead lock as a live lead ---------------

  def test_state_lead_ignores_stale_lock
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 601 Solo — delivering
      ## Log
    MD
    write_index(active: %w[601])
    dir = make_entry_dir("601", done: 0, total: 2)
    write_lock(dir, owner_agent: "plastic-enforcer", owner_session: "stale-session", mtime: NOW - 7200)

    out = render(roadmap_path("demo"), "state")
    row = out.lines.find { |l| l.start_with?("| **Delivering**") }
    # Intent 331f, D6: a stale lock reads "stale · N min", never a bare "idle" (which would
    # look identical to no lock at all) and never the dead session's own key.
    assert_includes row, "stale · 120 min"
    refute_includes row, "stale-session"
  end

  # --- R8: state Changed reads the last ledger event, never the clock ---------------

  def test_state_changed_reads_last_ledger_event
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 701 Solo — queued
    MD
    write_index
    write_ledger("demo", [
      "2026-09-01T00:00:00Z  created  demo roadmap",
      "2026-09-02T00:00:00Z  dispatched  701",
    ])

    out = render(roadmap_path("demo"), "state", now: Time.utc(2026, 9, 5, 23, 59, 59))
    row = out.lines.find { |l| l.start_with?("| **Changed**") }
    assert_includes row, "dispatched"
    assert_includes row, "2026-09-02"
    refute_includes row, "2026-09-05", "the clock must never stand in for the last ledger event"
  end

  # --- R9: delivered meta says "in progress" with no closed event -------------------

  def test_delivered_meta_in_progress_without_close
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 801 Solo — queued
    MD
    write_index
    write_ledger("demo", ["2026-09-01T00:00:00Z  created  demo roadmap"])

    out = render(roadmap_path("demo"), "delivered")
    meta = out.lines[1]
    assert_includes meta, "in progress"
  end

  # --- R10: the Merged column reads merged events only, matched by whole word ------

  def test_merged_column_reads_merged_events_only
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [x] 901 Alpha — delivered
      - [x] 902 Beta — delivered
    MD
    write_index(completed: %w[901 902])
    write_ledger("demo", [
      "2026-09-01T00:00:00Z  created  demo roadmap",
      "2026-09-02T00:00:00Z  merged  901 merged into alpha at abc1234",
      "2026-09-03T00:00:00Z  handoff  902 handed off to the next lead",
    ])

    out = render(roadmap_path("demo"), "delivered")
    row_901 = out.lines.find { |l| l.include?("| 901 |") }
    row_902 = out.lines.find { |l| l.include?("| 902 |") }
    assert_includes row_901, "abc1234"
    assert_includes row_902, "not recorded"
  end

  # --- R11: determinism - two renders of the same input are byte-identical ---------

  def test_render_roadmap_is_byte_identical
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [x] 1001 Alpha — delivered
      - [ ] 1002 Beta — queued
    MD
    write_index(completed: %w[1001], future: %w[1002])
    write_ledger("demo", ["2026-09-01T00:00:00Z  created  demo roadmap"])

    %w[plan state delivered].each do |verb|
      first = render(roadmap_path("demo"), verb)
      second = render(roadmap_path("demo"), verb)
      assert_equal first, second, "#{verb} must render byte-identically given the same inputs"
    end
  end

  # --- R12: a pipe in a goal or an entry title is escaped, never breaks the table ----

  def test_pipe_in_title_is_escaped
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      Goal with a | pipe in it.
      ## Batches
      ### Batch 1
      - [ ] 1101 Title with a | pipe — queued
    MD
    write_index

    out = render(roadmap_path("demo"), "plan")
    assert_includes out, "Goal with a \\| pipe in it."
    assert_includes out, "Title with a \\| pipe"
    entries_start = out.index("**Batches**")
    table_lines = out[entries_start..].lines.select { |l| l.start_with?("|") }
    row = table_lines.find { |l| l.include?("1101") }
    assert_equal 6, row.count("|"), "an escaped pipe must never add a table column"
  end

  # --- R15: a semicolon never ends the goal sentence, only a period does ------------

  def test_plan_goal_keeps_clauses_after_a_semicolon
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      First clause; second clause; third clause after two semicolons.
      ## Batches
      ### Batch 1
      - [ ] 1201 Solo — queued
    MD
    write_index

    out = render(roadmap_path("demo"), "plan")
    assert_includes out, "First clause; second clause; third clause after two semicolons."
  end

  # --- R16: a closed roadmap with no ledger FILE reads its real closed time ----------

  def test_delivered_meta_reads_log_when_no_ledger_file
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Waves
      ### Wave 1
      - [x] 1301 Solo — delivered
      ## Log
      - 2026-07-10 02:55 UTC roadmap closed.
    MD
    write_index(completed: %w[1301])
    # No demo.savepoint.md ledger file is written at all - manual-first.md's own shape.

    out = render(roadmap_path("demo"), "delivered")
    meta = out.lines[1]
    assert_includes meta, "2026-07-10 02:55 UTC"
    refute_includes meta, "in progress"
  end

  # --- R21: an id mentioned in passing in ANOTHER entry's merge line never fills this row -------

  def test_merged_column_ignores_an_id_mentioned_in_another_entrys_line
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [x] 216 Alpha — delivered
      - [x] 239 Beta — delivered
    MD
    write_index(completed: %w[216 239])
    write_ledger("demo", [
      "2026-08-12T15:43:19Z  merged  216 delivered and completed (merged b6ad017); doc sentence routed to 239; only 239 remains",
    ])

    out = render(roadmap_path("demo"), "delivered")
    row_216 = out.lines.find { |l| l.include?("| 216 |") }
    row_239 = out.lines.find { |l| l.include?("| 239 |") }
    assert_includes row_216, "b6ad017"
    assert_includes row_239, "not recorded"
  end

  # --- R22: a real per-entry merge filed under another event word is still read -----------------

  def test_merged_column_reads_a_merge_recorded_under_another_event_word
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [x] 249 Gamma — delivered
    MD
    write_index(completed: %w[249])
    write_ledger("demo", [
      "2026-08-12T12:49:25Z  dispatched  249 delivered and completed (merged 92cc32d); blind spot parked as 261; 250 activated with 257-corrected scope and dispatched",
    ])

    out = render(roadmap_path("demo"), "delivered")
    row = out.lines.find { |l| l.include?("| 249 |") }
    assert_includes row, "92cc32d"
  end

  # --- R17: state Frontier agrees with RoadmapQueue's own frontier selection --------

  def test_state_frontier_matches_roadmap_queue_frontier
    body = <<~MD
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [x] 1401 Solo — delivered

      ### Batch 2
      - [ ] 1402 Alpha — blocked

      ### Batch 3
      - [ ] 1403 Beta — queued
      ## Log
    MD
    write_roadmap("demo", body)
    write_index(completed: %w[1401], future: %w[1403])

    queue_result = RoadmapQueue.new(roadmaps_dir: @roadmaps, index_path: File.join(@home, "INDEX.md"), now: NOW).queue
    out = render(roadmap_path("demo"), "state")
    row = out.lines.find { |l| l.start_with?("| **Frontier**") }

    assert_equal "Batch 3", queue_result["frontier_wave"], "sanity: the blocked-only batch 2 must be skipped"
    assert_includes row, "Batch 3"
    refute_includes row, "Batch 2", "state's own frontier rule must never disagree with RoadmapQueue's"
  end

  # --- W8: state's Batches table carries the same Intent title column plan's already does ---

  def test_roadmap_state_batches_has_intent_column
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 501 Alpha title — queued
      ## Log
    MD
    write_index(future: %w[501])

    out = render(roadmap_path("demo"), "state")
    assert_includes out, "| Batch | Graph ID | Intent | Status | Progress | Lead |"
    row = out.lines.find { |l| l.include?("| 501 |") }
    refute_nil row
    assert_includes row, "Alpha title"
  end

  # --- W8a: the Intent cell spends whatever the row's other cells leave it, never a fixed width -

  def test_roadmap_state_intent_cell_takes_what_is_left
    long_title = (["Title"] * 60).join(" ")
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 601 #{long_title} — queued
      ## Log
    MD
    write_index(future: %w[601])
    make_entry_dir("601", done: 1, total: 2)

    out = render(roadmap_path("demo"), "state")
    row = out.lines.find { |l| l.include?("| 601 |") }
    refute_nil row
    assert_operator ScreenPaint.display_columns(row.chomp), :<=, 115,
                     "the row must stay bounded once the bar and lead are added"
    assert_includes row, "…", "a title this long must be truncated to leave room for the bar and lead"
  end

  # --- W8b: one long row's table-wide shrink must never re-truncate another row's own budget -

  def test_roadmap_state_rows_keep_their_own_intent_budget
    long_title = (["Title"] * 60).join(" ")
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 701 #{long_title} — queued
      - [ ] 702 Short — queued
      ## Log
    MD
    write_index(future: %w[701 702])

    out = render(roadmap_path("demo"), "state")
    row_short = out.lines.find { |l| l.include?("| 702 |") }
    refute_nil row_short
    assert_includes row_short, "| Short |",
                     "a short row's Intent cell must not be re-truncated just because another row is long"
  end

  # --- W8c/A6: an escaped pipe never adds or drops a column in the widened 6-column table ---

  def test_roadmap_state_row_keeps_six_columns_with_a_piped_title
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 1101 Title with a | pipe — queued
      ## Log
    MD
    write_index(future: %w[1101])

    out = render(roadmap_path("demo"), "state")
    row = out.lines.find { |l| l.include?("| 1101 |") }
    refute_nil row
    assert_equal 8, row.count("|"), "an escaped pipe must never add or drop a column in the 6-column table"
  end

  # --- W8d/B1: the old 5-column Batches header must never survive anywhere -------------------

  def test_roadmap_state_never_prints_the_old_batches_header
    write_roadmap("demo", <<~MD)
      # Roadmap: Demo
      ## Goal
      test.
      ## Batches
      ### Batch 1
      - [ ] 1201 Solo — queued
      ## Log
    MD
    write_index(future: %w[1201])

    out = render(roadmap_path("demo"), "state")
    refute_includes out, "| Batch | Graph ID | Status | Progress | Lead |"
    refute_includes out, "| Wave | Graph ID | Status | Progress | Lead |"
  end
end
