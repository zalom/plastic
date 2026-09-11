# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/node_ledger"

# Intent 335 (G2), S2: the transition line and its reader. Matrix rows 2.1-2.45 in
# actions/ACTION_1.md. Hermetic: Dir.mktmpdir fixtures, no environment read.
class NodeLedgerTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def setup
    @dir = Dir.mktmpdir("node-ledger")
    @path = File.join(@dir, "savepoint.md")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def build(subject:, state:, fields: {}, comment: nil, now: Time.utc(2026, 9, 8, 19, 10, 40))
    NodeLedger.transition_line(subject: subject, state: state, fields: fields, comment: comment, now: now)
  end

  RUNNING_FIELDS = { holder: "auto-ce50567419", expires: "2026-09-08T19:40:40Z", packet: "1f3c9a2", model: "sonnet" }.freeze

  # --- 2.1-2.9: building a line ------------------------------------------------

  def test_transition_line_splits_into_exactly_three_fields
    line = build(subject: "n1", state: "running", fields: RUNNING_FIELDS)
    parts = line.chomp.split(/\s{2,}/)
    assert_equal 3, parts.length
  end

  def test_a_value_containing_two_consecutive_spaces_still_splits_into_three_fields
    line = build(subject: "Intent", state: "needs_decision", fields: { question: "rewrite  the docs?" })
    parts = line.chomp.split(/\s{2,}/)
    assert_equal 3, parts.length
    assert_includes line, "rewrite the docs?"
    refute_includes line.sub(/\A\S+  \S+  /, ""), "  "
  end

  def test_a_tab_in_a_value_is_refused
    assert_raises(ArgumentError) do
      build(subject: "Intent", state: "needs_decision", fields: { question: "a\tb" })
    end
  end

  def test_a_comment_with_a_double_space_is_collapsed
    line = build(subject: "n1", state: "planned", comment: "two  spaces  here")
    parts = line.chomp.split(/\s{2,}/)
    assert_equal 3, parts.length
    assert_includes line, "(two spaces here)"
  end

  # 7.6 (post-execution review) - a carriage return, vertical tab or form feed beside a
  # space is a two-whitespace run too, so it must collapse just like two literal spaces.
  def test_a_carriage_return_in_a_value_is_collapsed_and_the_line_stays_three_fields
    line = build(subject: "n1", state: "blocked", fields: { reason: "waiting \r on review" })
    parts = line.chomp.split(/\s{2,}/)
    assert_equal 3, parts.length
    assert_includes line, "waiting on review"
    refute_match(/\r/, line)
  end

  # 7.7 (post-execution review) - a field key FIELD_TOKEN_RE cannot read back must be
  # refused at the emitter, before it becomes an unparseable pair that swallows every
  # field rendered after it.
  def test_a_field_key_the_parser_cannot_read_is_refused
    assert_raises(ArgumentError) do
      build(subject: "n1", state: "planned", fields: { "Sha" => "1" })
    end
  end

  def test_transition_line_timestamp_is_utc_iso8601
    line = build(subject: "n1", state: "planned")
    timestamp = line.split(/\s{2,}/).first
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, timestamp)
  end

  def test_fields_render_in_a_stable_declared_order
    a = build(subject: "n1", state: "running",
              fields: { model: "sonnet", packet: "1f3c9a2", holder: "auto-x", expires: "2026-09-08T19:40:40Z" })
    b = build(subject: "n1", state: "running",
              fields: { holder: "auto-x", expires: "2026-09-08T19:40:40Z", model: "sonnet", packet: "1f3c9a2" })
    assert_equal a, b
    rest = a.chomp.split(/\s{2,}/).last
    assert_equal "running holder=auto-x expires=2026-09-08T19:40:40Z packet=1f3c9a2 model=sonnet", rest
  end

  # --- Intent 340b, G7c, n1: harness= is an accepted field on every state ----

  # The minimal valid fields hash per state, so a line can be built at all
  # (transition_line raises ArgumentError on a missing required field) -
  # mirrors NodeLedger::REQUIRED_FIELDS plus done's own commit-or-verdict
  # evidence rule.
  MINIMAL_FIELDS_BY_STATE = {
    "planned" => {},
    "running" => RUNNING_FIELDS,
    "done" => { gates: "g", commit: "c1" },
    "failed_verification" => { gates: "g", reason: "r" },
    "needs_decision" => { question: "q" },
    "blocked" => { reason: "r" },
    "deferred" => { reason: "r" },
    "superseded" => { by: "n2" },
    "abandoned" => { reason: "r" },
    "reclaimed" => { holder: "h", expired: "2026-09-08T19:40:40Z" },
  }.freeze

  # 1.15: harness= rides as an accepted field, required by none, on every one
  # of the ten states - written and read back under its own key, never
  # silently dropped or misfiled, on states well beyond `running`.
  def test_harness_field_round_trips_on_every_state
    NodeLedger::STATES.each do |state|
      fields = MINIMAL_FIELDS_BY_STATE.fetch(state).merge(harness: "codex")
      line = build(subject: "n1", state: state, fields: fields)
      parsed = NodeLedger.parse_transition_line(line)
      assert_equal "codex", parsed[:fields]["harness"], "state #{state} must round-trip harness="
      refute NodeLedger.torn?(line), "state #{state} with harness= must not read as torn: #{line.inspect}"
    end
  end

  # 1.17: harness= renders in a stable, DECLARED FIELD_ORDER position - right
  # after model=, never sorted into the trailing extras. `core_drift` (a real
  # extra field, alphabetically BEFORE "harness") is the differentiator: an
  # unlisted `harness` would sort as an extra alongside it, alphabetically
  # ahead of it ("core_drift=... harness=..."); a declared `harness` renders
  # with the other known dispatch-time fields, ahead of every extra
  # ("... harness=codex core_drift=true").
  def test_harness_field_order_is_stable
    fields = { model: "sonnet", packet: "1f3c9a2", holder: "auto-x", expires: "2026-09-08T19:40:40Z",
               harness: "codex", core_drift: "true" }
    line = build(subject: "n1", state: "running", fields: fields)
    rest = line.chomp.split(/\s{2,}/).last
    assert_equal "running holder=auto-x expires=2026-09-08T19:40:40Z packet=1f3c9a2 model=sonnet " \
                 "harness=codex core_drift=true", rest

    # Insertion order must never matter (mirrors test_fields_render_in_a_stable_declared_order).
    reordered = build(subject: "n1", state: "running",
                       fields: { core_drift: "true", harness: "codex", holder: "auto-x",
                                 expires: "2026-09-08T19:40:40Z", model: "sonnet", packet: "1f3c9a2" })
    assert_equal line, reordered
  end

  def test_a_value_with_a_single_space_is_double_quoted_and_round_trips
    line = build(subject: "Intent", state: "needs_decision", fields: { question: "two words" })
    assert_match(/question="two words"/, line)
    parsed = NodeLedger.parse_transition_line(line)
    assert_equal "two words", parsed[:fields]["question"]
  end

  def test_quotes_and_backslashes_in_a_value_round_trip
    tricky = 'a "quoted" value with a \\backslash'
    line = build(subject: "Intent", state: "needs_decision", fields: { question: tricky })
    parsed = NodeLedger.parse_transition_line(line)
    assert_equal tricky, parsed[:fields]["question"]
  end

  def test_a_newline_in_a_value_is_refused
    assert_raises(ArgumentError) do
      build(subject: "Intent", state: "needs_decision", fields: { question: "a\nb" })
    end
  end

  # --- 2.10-2.16: parsing and torn detection -----------------------------------

  def test_a_stage_line_is_not_a_transition_candidate
    refute Savepoint.transition_candidate?("2026-09-08T19:10:40Z  How  checklist.md created")
  end

  def test_a_lock_takeover_line_is_not_a_transition_candidate
    refute Savepoint.transition_candidate?(
      "2026-09-08T19:10:40Z  Lock  takeover: auto-x reclaimed delivery lock from auto-y"
    )
  end

  def test_a_trailing_comment_is_preserved_and_ignored
    line = build(subject: "n4", state: "reclaimed", fields: { holder: "auto-x", expired: "2026-09-08T20:01:00Z" },
                 comment: "crash sweep")
    parsed = NodeLedger.parse_transition_line(line)
    assert_equal "auto-x", parsed[:fields]["holder"]
    assert_equal "2026-09-08T20:01:00Z", parsed[:fields]["expired"]
    assert_equal "crash sweep", parsed[:comment]
  end

  def test_a_state_token_outside_the_vocabulary_is_torn
    assert NodeLedger.torn?("2026-09-08T19:10:40Z  n1  runn holder=auto-x")
  end

  def test_a_valid_state_missing_a_required_field_is_torn
    assert NodeLedger.torn?("2026-09-08T19:10:40Z  n1  running holder=auto-ce5")
  end

  def test_a_torn_line_is_ignored_by_status
    File.write(@path, "2026-09-08T19:10:40Z  n1  running holder=auto-ce5\n")
    assert_equal "planned", NodeLedger.status_for(@path, "n1")
  end

  def test_no_stage_line_is_ever_reported_torn
    File.write(@path, "2026-09-08T19:10:40Z  How  checklist.md created\n")
    assert_empty NodeLedger.anomalies(@path)
  end

  # --- 2.17-2.28: required fields and vocabulary -------------------------------

  def test_running_without_packet_is_refused_by_name
    fields = RUNNING_FIELDS.reject { |k, _| k == :packet }
    error = assert_raises(ArgumentError) { build(subject: "n1", state: "running", fields: fields) }
    assert_match(/packet/, error.message)
  end

  def test_running_without_model_is_refused_by_name
    fields = RUNNING_FIELDS.reject { |k, _| k == :model }
    error = assert_raises(ArgumentError) { build(subject: "n1", state: "running", fields: fields) }
    assert_match(/model/, error.message)
  end

  def test_done_and_reclaimed_are_accepted_without_model
    assert_empty NodeLedger.missing_fields("done", { gates: "suite", commit: "abc" })
    assert_empty NodeLedger.missing_fields("reclaimed", { holder: "auto-x", expired: "2026-09-08T20:01:00Z" })
  end

  def test_model_is_accepted_on_any_state_when_supplied
    line = build(subject: "n1", state: "done", fields: { gates: "suite", commit: "abc", model: "sonnet" })
    parsed = NodeLedger.parse_transition_line(line)
    assert_equal "sonnet", parsed[:fields]["model"]
  end

  def test_done_without_gates_is_refused
    error = assert_raises(ArgumentError) { build(subject: "n1", state: "done", fields: { commit: "abc" }) }
    assert_match(/gates/, error.message)
  end

  def test_done_without_any_evidence_field_is_refused
    error = assert_raises(ArgumentError) { build(subject: "n1", state: "done", fields: { gates: "suite" }) }
    assert_match(/commit or verdict/, error.message)
  end

  def test_done_without_holder_is_accepted_and_unattributed
    line = build(subject: "n1", state: "done", fields: { gates: "suite", commit: "abc" })
    parsed = NodeLedger.parse_transition_line(line)
    refute NodeLedger.attributed?(parsed)
  end

  def test_reclaimed_without_expired_is_refused
    error = assert_raises(ArgumentError) { build(subject: "n1", state: "reclaimed", fields: { holder: "auto-x" }) }
    assert_match(/expired/, error.message)
  end

  def test_superseded_without_by_is_refused
    error = assert_raises(ArgumentError) { build(subject: "n1", state: "superseded", fields: {}) }
    assert_match(/by/, error.message)
  end

  def test_a_refused_append_leaves_the_ledger_byte_identical
    File.write(@path, "n1  planned\n")
    before = File.read(@path)
    assert_raises(ArgumentError) do
      NodeLedger.append_transition(@path, subject: "n1", state: "done", fields: {})
    end
    assert_equal before, File.read(@path)
  end

  def test_an_unknown_state_is_refused_by_the_appender
    assert_raises(ArgumentError) do
      NodeLedger.append_transition(@path, subject: "n1", state: "banana", fields: {})
    end
    refute File.exist?(@path)
  end

  def test_states_is_exactly_the_ten_tokens_of_d1
    expected = %w[planned running done failed_verification needs_decision blocked deferred
                  superseded abandoned reclaimed]
    assert_equal expected.sort, NodeLedger::STATES.sort
    assert_equal 10, NodeLedger::STATES.length
  end

  # --- 2.29-2.30: dedup ---------------------------------------------------------

  def test_two_identical_transition_lines_both_land
    NodeLedger.append_transition(@path, subject: "n1", state: "running", fields: RUNNING_FIELDS)
    NodeLedger.append_transition(@path, subject: "n1", state: "failed_verification",
                                  fields: { gates: "suite", reason: "flaky" })
    NodeLedger.append_transition(@path, subject: "n1", state: "running", fields: RUNNING_FIELDS)
    lines = File.readlines(@path)
    assert_equal 3, lines.length
    assert_equal 2, lines.count { |l| l.include?("running") }
  end

  def test_no_stage_token_in_the_tree_matches_a_transition_subject
    %w[What Why How Exec Done Review Commit Lock Tier].each do |stage|
      refute_equal Savepoint::INTENT_SUBJECT, stage
      refute stage.match?(Savepoint::NODE_SUBJECT_RE), "#{stage} must not match NODE_SUBJECT_RE"
    end
  end

  # --- 2.31-2.35: status ---------------------------------------------------------

  def test_status_is_the_last_line_in_file_order_not_the_latest_timestamp
    File.write(@path,
               build(subject: "n1", state: "running", fields: RUNNING_FIELDS, now: Time.utc(2026, 9, 8, 20, 0, 0)) +
               build(subject: "n1", state: "done", fields: { gates: "suite", commit: "abc" },
                     now: Time.utc(2026, 9, 8, 19, 0, 0)))
    assert_equal "done", NodeLedger.status_for(@path, "n1")
  end

  def test_status_is_computed_per_subject
    File.write(@path,
               build(subject: "n1", state: "running", fields: RUNNING_FIELDS) +
               build(subject: "n2", state: "planned"))
    assert_equal "running", NodeLedger.status_for(@path, "n1")
    assert_equal "planned", NodeLedger.status_for(@path, "n2")
  end

  def test_intent_and_node_subjects_do_not_collide
    File.write(@path,
               build(subject: "Intent", state: "needs_decision", fields: { question: "q?" }) +
               build(subject: "n1", state: "planned"))
    statuses = NodeLedger.status(@path)
    assert_equal "needs_decision", statuses["Intent"]
    assert_equal "planned", statuses["n1"]
  end

  def test_reclaimed_resolves_to_planned
    File.write(@path, build(subject: "n1", state: "reclaimed",
                             fields: { holder: "auto-x", expired: "2026-09-08T20:01:00Z" }))
    assert_equal "planned", NodeLedger.status_for(@path, "n1")
    assert_equal "planned", NodeLedger.resolved_state("reclaimed")
  end

  def test_an_unseen_subject_reads_as_planned
    File.write(@path, build(subject: "n1", state: "planned"))
    assert_equal "planned", NodeLedger.status_for(@path, "n99")
  end

  # --- 2.36-2.39: attribution and anomalies -------------------------------------

  def test_a_line_without_holder_is_unattributed
    line = build(subject: "n1", state: "done", fields: { gates: "suite", commit: "abc" })
    parsed = NodeLedger.parse_transition_line(line)
    refute NodeLedger.attributed?(parsed)
  end

  def test_unattributed_is_not_torn
    line = build(subject: "n1", state: "done", fields: { gates: "suite", commit: "abc" })
    refute NodeLedger.torn?(line)
    parsed = NodeLedger.parse_transition_line(line)
    refute NodeLedger.attributed?(parsed)
  end

  def test_anomalies_lists_torn_and_unattributed_lines_with_reasons
    File.write(@path,
               "2026-09-08T19:10:40Z  n1  running holder=auto-ce5\n" +
               build(subject: "n2", state: "done", fields: { gates: "suite", commit: "abc" }))
    found = NodeLedger.anomalies(@path)
    assert_equal 2, found.length
    assert(found.any? { |a| a[:reason].include?("torn") })
    assert(found.any? { |a| a[:reason].include?("unattributed") })
  end

  def test_anomalies_on_a_clean_or_absent_ledger_is_empty
    assert_empty NodeLedger.anomalies(File.join(@dir, "no-such-file.md"))
    File.write(@path, build(subject: "n1", state: "running", fields: RUNNING_FIELDS))
    assert_empty NodeLedger.anomalies(@path)
  end

  # --- 2.40-2.41: guarded append -------------------------------------------------

  def test_append_transition_goes_through_the_guard
    calls = []
    fake_guard = Object.new
    fake_guard.define_singleton_method(:call) do |path, **opts, &blk|
      calls << [path, opts]
      File.open(path, "a") { |io| io.write(blk.call("")) }
      :written
    end
    NodeLedger.append_transition(@path, subject: "n1", state: "planned", guard: fake_guard)
    assert_equal 1, calls.length
    assert_equal @path, calls.first[0]
    # 7.10 (post-execution review): pin strict: true. Spec D12a forbids a non-strict
    # guard for transition appends; a regression to strict: false must fail this test.
    assert_equal({ strict: true }, calls.first[1])
  end

  def test_append_transition_propagates_unavailable
    require_relative "../scripts/lib/guarded_append"
    fake_guard = Object.new
    fake_guard.define_singleton_method(:call) { |*_args, **_opts| raise GuardedAppend::Unavailable, "nope" }
    assert_raises(GuardedAppend::Unavailable) do
      NodeLedger.append_transition(@path, subject: "n1", state: "planned", guard: fake_guard)
    end
  end

  # --- 7.1-7.3 (post-execution review): the readiness decision under the guard's hold ---

  # 7.2 - a precondition must be evaluated against the CONTENT THE GUARD READ under its
  # hold, never a stale copy captured before the lock was taken.
  def test_append_transition_evaluates_the_precondition_against_the_guarded_content
    File.write(@path, "2026-09-08T18:00:00Z  n1  planned\n")
    seen_content = nil
    precondition = ->(content) { seen_content = content; true }
    NodeLedger.append_transition(@path, subject: "n1", state: "running", fields: RUNNING_FIELDS,
                                  precondition: precondition)
    assert_equal "2026-09-08T18:00:00Z  n1  planned\n", seen_content
  end

  # 7.3 - a refusing precondition must write nothing and report the refusal
  # distinguishably from a successful write (spec "Approach": "a block returning nil is
  # a refusal and writes nothing").
  def test_a_refusing_precondition_writes_nothing_and_reports_the_refusal
    result = NodeLedger.append_transition(@path, subject: "n1", state: "planned",
                                           precondition: ->(_content) { false })
    assert_equal :refused, result
    assert_equal "", File.read(@path)
  end

  # --- 2.44: encoding -------------------------------------------------------------

  def test_an_invalid_byte_in_the_ledger_does_not_raise
    File.open(@path, "wb") do |io|
      io.write(build(subject: "n1", state: "planned"))
      io.write("2026-09-08T19:10:40Z  n2  runn\xFFing holder=auto-x\n")
    end
    result = nil
    assert_silent_from_encoding_error { result = NodeLedger.entries(@path) }
    refute_nil result
  end

  def assert_silent_from_encoding_error
    yield
  rescue ArgumentError, Encoding::CompatibilityError => e
    flunk "a stray invalid byte must not raise out of the parser: #{e.class}: #{e.message}"
  end

  # --- 2.45: load order -----------------------------------------------------------

  def test_savepoint_still_loads_standalone
    Dir.mktmpdir("savepoint-standalone") do |tmp|
      env = { "RUBYOPT" => nil, "PLASTIC_TMP" => tmp, "CLAUDE_CODE_SESSION_ID" => nil }
      lib = File.join(REPO, "scripts", "lib", "savepoint.rb")
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", "require #{lib.inspect}; puts $LOADED_FEATURES")
      assert status.success?, "savepoint.rb does not load standalone: #{err}"
      loaded = out.lines.map(&:strip)
      project = loaded.select { |f| f.start_with?("#{REPO}/") }.map { |f| f.sub("#{REPO}/", "") }.sort
      assert_equal %w[scripts/lib/savepoint.rb], project,
        "NodeLedger must require savepoint.rb, never the other way; savepoint.rb must load standalone"
    end
  end
end
