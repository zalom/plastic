# encoding: UTF-8
# frozen_string_literal: true

require "time"
require "tmpdir"
require_relative "savepoint"
require_relative "node_ledger"
require_relative "graph_file"
require_relative "node_file"

# GraphMeasure (intent 343, G10, n1): the ledger reader half of measurement.
# `GraphMeasure.read(intent_dir)` takes one intent directory and returns one
# frozen measurement record. Pure and dependency-injected: every path and
# every clock is a keyword argument with a real default, it reads no
# environment variable, and it writes nothing to the intent directory (any
# scratch file this module creates to work around GraphFile/NodeFile's lack
# of UTF-8 scrubbing lives in its own Dir.mktmpdir, never inside intent_dir).
#
# It adds no second parser and no second estimator. `NodeLedger` owns the
# transition-line format, the closed state vocabulary, torn detection and
# attribution; `Savepoint` owns the stage-line vocabulary; `GraphFile` owns
# `## Graph`; `NodeFile` owns the envelope and `KIND_PREFIX`. This module
# composes them and computes what none of them computes: time.
module GraphMeasure
  module_function

  # Spec D5: 45 minutes, a named constant and an injectable argument (row 1.15).
  DEFAULT_GAP_THRESHOLD_MINUTES = 45.0

  # Every state but the two that can never CLOSE an attempt (spec matrix rows
  # 1.4-1.9): `planned` is never written, `running` OPENS an attempt.
  TERMINAL_STATES = (NodeLedger::STATES - %w[planned running]).freeze

  SAVEPOINT_FILE = "savepoint.md"

  # {ok:, scaffold:, clock:, sessions:, pauses:, active_seconds:,
  # paused_seconds:, nodes:, anomalies:, suite_history:, gap_threshold_minutes:}.
  # Never raises: a missing or empty savepoint.md, an unparsable graph.md, an
  # invalid-UTF-8 node file, all resolve to an empty or partial record rather
  # than an exception (spec D3, D4, rows 1.30, 1.31).
  def read(intent_dir, now: Time.now, gap_threshold_minutes: DEFAULT_GAP_THRESHOLD_MINUTES)
    dir = File.expand_path(intent_dir.to_s)
    content = read_content(File.join(dir, SAVEPOINT_FILE))
    events = all_events(content)

    transition_events = events.select { |e| e[:kind] == :transition }
    entries_by_subject = group_by_subject(transition_events)

    attempts_by_subject = entries_by_subject.each_with_object({}) do |(subject, subject_entries), memo|
      memo[subject] = build_attempts(subject_entries, now)
    end

    clock = build_clock(events)
    threshold_seconds = gap_threshold_minutes.to_f * 60

    active_running_intervals = merge_running_intervals(attempts_by_subject, now)
    pauses = compute_pauses(events, active_running_intervals, threshold_seconds, clock, now)
    sessions = complement(pauses, clock[:start], clock[:end])
    # B2 (v1 review): `complement` returns `[]` whenever the clock has no end
    # (an intent with no `Done` line yet), and summing an empty session list
    # against a real running-to-terminal span silently produced `0.0`
    # instead of `nil` - every attempt in an open intent reported "active
    # 0.0 min" no matter how long it actually ran (reproduced against this
    # very intent's own live savepoint.md while n8 was `running`: n4's
    # closed attempt showed "raw 1094.4 / active 0.0"). An active span is
    # only knowable once the delivery clock itself has both ends.
    clock_known = !!(clock[:start] && clock[:end])
    fill_active_spans!(attempts_by_subject, sessions, clock_known)

    graph = load_graph(dir)
    node_ids = (graph[:node_ids] + attempts_by_subject.keys.reject { |s| s == Savepoint::INTENT_SUBJECT }).uniq
    kind_of, kind_source_of = resolve_kinds(dir, node_ids)
    hop_ever_seen = transition_events.any? { |e| e[:fields].key?("hop") }
    review_fix_memo = {}

    nodes = node_ids.each_with_object({}) do |id, memo|
      attempts = attempts_by_subject[id] || []
      kind = kind_of[id]
      memo[id] = {
        kind: kind,
        kind_source: kind_source_of[id] || :unknown,
        review_fix: kind == "work" ? review_fix?(id, kind_of, graph[:edges], review_fix_memo) : false,
        status: NodeLedger.status_for_content(content, id),
        model: node_model(attempts),
        hop: node_hop(attempts, hop_ever_seen),
        attempts: attempts,
      }
    end

    anomalies = split_anomalies(NodeLedger.anomalies(File.join(dir, SAVEPOINT_FILE)))

    record = {
      ok: true,
      gap_threshold_minutes: gap_threshold_minutes.to_f,
      scaffold: clock[:scaffold],
      clock: { start: clock[:start], end: clock[:end], anchor: clock[:anchor],
                wall_clock_seconds: clock[:wall_clock_seconds] },
      sessions: sessions,
      pauses: pauses,
      active_seconds: clock[:start] && clock[:end] ? sessions.sum { |s| s[:end] - s[:start] } : :unavailable,
      paused_seconds: clock[:start] && clock[:end] ? pauses.sum { |p| p[:end] - p[:start] } : :unavailable,
      nodes: nodes,
      anomalies: anomalies,
      suite_history: suite_history(transition_events),
    }

    deep_freeze(record)
  end

  # --- reading the raw ledger --------------------------------------------------

  def read_content(path)
    return "" unless path && File.exist?(path)

    File.read(path).scrub
  end
  private_class_method :read_content

  # One combined, file-ordered event list over EVERY line of savepoint.md,
  # transition lines delegated to NodeLedger's own primitives (row 1.1: no
  # second parser), stage/Report/Lock/Commit lines classified locally because
  # NodeLedger.entries deliberately excludes them (Savepoint owns that
  # vocabulary). Never sorted by timestamp (row 1.27): callers walk this list
  # in the order returned.
  def all_events(content)
    content.to_s.each_line.filter_map do |raw|
      line = raw.chomp
      next nil if line.strip.empty?

      if Savepoint.transition_candidate?(line)
        parsed = NodeLedger.parse_transition_line(line)
        {
          kind: :transition,
          raw: line,
          timestamp: parsed && parsed[:timestamp],
          subject: parsed ? parsed[:subject] : line.split(/\s{2,}/)[1],
          state: parsed && parsed[:state],
          fields: parsed ? parsed[:fields] : {},
          comment: parsed && parsed[:comment],
          torn: NodeLedger.torn?(line),
        }
      else
        parts = line.split(/\s{2,}/, 3)
        next nil if parts.length < 2

        { kind: :stage, raw: line, timestamp: parts[0], subject: parts[1], rest: parts[2].to_s }
      end
    end
  end
  private_class_method :all_events

  def group_by_subject(transition_events)
    transition_events.each_with_object(Hash.new { |h, k| h[k] = [] }) do |entry, memo|
      memo[entry[:subject]] << entry unless entry[:torn]
    end
  end
  private_class_method :group_by_subject

  def parse_time(ts)
    return nil unless ts

    Time.iso8601(ts.to_s)
  rescue ArgumentError
    nil
  end
  private_class_method :parse_time

  # --- clock: spec D5.1 --------------------------------------------------------

  # D20: the clock anchors on the first `Why` line when one exists. An intent
  # whose savepoint.md carries no `Why` line at all (337 is the real example)
  # has nothing for that anchor to start from, so the clock falls back to the
  # FIRST ledger line of any kind (stage or transition) and the record names
  # which anchor it used (row 3.23). The scaffold gap (`What` line to `Why`
  # line) is a distance between two SPECIFIC stage lines; without a `Why` line
  # that distance does not exist, so the fallback reports it `unavailable`
  # rather than inventing a number against the wrong anchor.
  def build_clock(events)
    stage_events = events.select { |e| e[:kind] == :stage }
    what_event = stage_events.find { |e| e[:subject] == "What" }
    why_event = stage_events.find { |e| e[:subject] == "Why" }
    done_event = stage_events.reverse.find { |e| e[:subject] == "Done" }

    what_at = what_event && parse_time(what_event[:timestamp])
    why_at = why_event && parse_time(why_event[:timestamp])
    done_at = done_event && parse_time(done_event[:timestamp])

    anchor = :why
    start_at = why_at
    unless start_at
      first_with_time = events.find { |e| parse_time(e[:timestamp]) }
      start_at = first_with_time && parse_time(first_with_time[:timestamp])
      anchor = :first_line
    end

    {
      start: start_at,
      end: done_at,
      anchor: anchor,
      wall_clock_seconds: (start_at && done_at) ? (done_at - start_at) : nil,
      scaffold: {
        what_at: what_at,
        why_at: why_at,
        gap_seconds: (anchor == :why && what_at && why_at) ? (why_at - what_at) : nil,
      },
    }
  end
  private_class_method :build_clock

  # --- attempts: spec rows 1.4-1.9, 1.6 ----------------------------------------

  def build_attempts(subject_entries, now)
    attempts = []
    open_running = nil
    subject_entries.each do |entry|
      case entry[:state]
      when "running"
        attempts << finalize_attempt(open_running, nil, now) if open_running
        open_running = entry
      when *TERMINAL_STATES
        attempts << finalize_attempt(open_running, entry, now)
        open_running = nil
      end
    end
    attempts << finalize_attempt(open_running, nil, now) if open_running
    attempts
  end
  private_class_method :build_attempts

  # `fields` merges the RUNNING line's fields under the TERMINAL line's (spec
  # rows 1.25, 1.26): most fields (`holder`, `model`) are restated on both, but
  # `hop=` is written once, on the `running` line only (row 3.10's real-ledger
  # shape), and a terminal-only read silently lost it. A key present on both
  # takes the terminal's value, which stays the more authoritative line.
  def finalize_attempt(running, terminal, now)
    running_at = running && parse_time(running[:timestamp])
    terminal_at = terminal && parse_time(terminal[:timestamp])
    running_fields = (running && running[:fields]) || {}
    terminal_fields = (terminal && terminal[:fields]) || {}
    fields = running_fields.merge(terminal_fields)

    span_note =
      if running_at && terminal_at then nil
      elsif running_at && !terminal_at then :open
      elsif !running_at && terminal_at then :no_running
      end

    span_seconds = (running_at && terminal_at) ? [terminal_at - running_at, 0].max : nil
    suite_raw = fields["suite"]
    suite = if terminal && terminal[:state] == "done"
      present?(suite_raw) ? parse_suite(suite_raw) : :unavailable
    elsif present?(suite_raw)
      parse_suite(suite_raw)
    end

    {
      holder: fields["holder"],
      running_at: running_at,
      terminal_at: terminal_at,
      terminal_state: terminal && terminal[:state],
      completing: terminal ? terminal[:state] == "done" : false,
      span_seconds: span_seconds,
      span_note: span_note,
      raw_span_seconds: span_seconds,
      active_span_seconds: nil, # filled by fill_active_spans!
      running_open: running_at && !terminal_at ? true : false,
      suite: suite,
      fields: fields,
      comment: (terminal && terminal[:comment]) || (running && running[:comment]),
    }
  end
  private_class_method :finalize_attempt

  def fill_active_spans!(attempts_by_subject, sessions, clock_known)
    attempts_by_subject.each_value do |attempts|
      attempts.each do |attempt|
        next unless attempt[:span_seconds]

        attempt[:active_span_seconds] = clock_known ? intersect_with_sessions(attempt[:running_at], attempt[:terminal_at], sessions) : nil
      end
    end
  end
  private_class_method :fill_active_spans!

  def intersect_with_sessions(start_t, end_t, sessions)
    return nil unless start_t && end_t

    total = 0.0
    sessions.each do |s|
      lo = [start_t, s[:start]].max
      hi = [end_t, s[:end]].min
      total += (hi - lo) if hi > lo
    end
    total
  end
  private_class_method :intersect_with_sessions

  # --- pauses and sessions: spec D5.2, D5.3, rows 1.12-1.17 --------------------

  def merge_running_intervals(attempts_by_subject, now)
    intervals = attempts_by_subject.values.flatten.filter_map do |a|
      next nil unless a[:running_at]

      { start: a[:running_at], end: a[:terminal_at] || now }
    end
    merge_time_ranges(intervals)
  end
  private_class_method :merge_running_intervals

  def compute_pauses(events, active_running_intervals, threshold_seconds, clock, now)
    clock_start, clock_end = clock[:start], clock[:end]
    raw = explicit_pauses(events) + generic_pauses(events, active_running_intervals, threshold_seconds)
    normalized = raw.filter_map do |p|
      s = p[:start]
      e = p[:end] || clock_end || now
      next nil unless s
      next nil if clock_start && s < clock_start
      s = clock_start if clock_start && s < clock_start
      e = clock_end if clock_end && e > clock_end
      next nil if e <= s

      { start: s, end: e, opened_by: p[:opened_by], closed_by: p[:closed_by] }
    end
    merge_pauses(normalized)
  end
  private_class_method :compute_pauses

  # A `Report` line whose text begins `PAUSED` opens a pause at its own stamp
  # (spec D5.3); a `Lock takeover:` line closes a pause opened at the last
  # ledger line before it, regardless of that line's own kind.
  def explicit_pauses(events)
    pauses = []
    events.each_with_index do |ev, i|
      if ev[:kind] == :stage && ev[:subject] == "Lock" && ev[:rest].to_s.start_with?("takeover:")
        prev = i.positive? ? events[i - 1] : nil
        next unless prev

        s = parse_time(prev[:timestamp])
        e = parse_time(ev[:timestamp])
        pauses << { start: s, end: e, opened_by: :previous_line, closed_by: :lock_takeover } if s && e
      elsif ev[:kind] == :stage && ev[:subject] == "Report" && ev[:rest].to_s.strip.start_with?("PAUSED")
        nxt = events[i + 1]
        s = parse_time(ev[:timestamp])
        e = nxt && parse_time(nxt[:timestamp])
        pauses << { start: s, end: e, opened_by: :paused_report, closed_by: nxt ? :next_line : nil } if s
      end
    end
    pauses
  end
  private_class_method :explicit_pauses

  # A gap between two adjacent ledger lines longer than the threshold is a
  # pause only when no subject holds an open `running` attempt across it
  # (spec D5.2, row 1.12). Timestamps are read in file order and never
  # assumed to ascend (row 1.27): a non-positive gap is simply not a pause,
  # never an error.
  def generic_pauses(events, active_running_intervals, threshold_seconds)
    pauses = []
    times = events.map { |e| parse_time(e[:timestamp]) }
    (events.length - 1).times do |i|
      t1 = times[i]
      t2 = times[i + 1]
      next unless t1 && t2

      gap = t2 - t1
      next if gap <= threshold_seconds
      next if active_running_intervals.any? { |iv| iv[:start] < t2 && iv[:end] > t1 }

      pauses << { start: t1, end: t2, opened_by: :gap, closed_by: :gap }
    end
    pauses
  end
  private_class_method :generic_pauses

  def merge_time_ranges(intervals)
    sorted = intervals.compact.reject { |iv| iv[:start].nil? || iv[:end].nil? }.sort_by { |iv| iv[:start] }
    merged = []
    sorted.each do |iv|
      last = merged.last
      if last && iv[:start] <= last[:end]
        last[:end] = iv[:end] if iv[:end] > last[:end]
      else
        merged << { start: iv[:start], end: iv[:end] }
      end
    end
    merged
  end
  private_class_method :merge_time_ranges

  def merge_pauses(pauses)
    sorted = pauses.compact.sort_by { |p| p[:start] }
    merged = []
    sorted.each do |p|
      last = merged.last
      if last && p[:start] <= last[:end]
        if p[:end] > last[:end]
          last[:end] = p[:end]
          last[:closed_by] = p[:closed_by]
        end
      else
        merged << p.dup
      end
    end
    merged
  end
  private_class_method :merge_pauses

  # The complement of `pauses` inside [start, finish]: the active session
  # intervals (spec D5's "the two evidence kinds bound a gap from opposite
  # ends", row 1.17's reconciliation).
  def complement(pauses, start, finish)
    return [] unless start && finish

    sessions = []
    cursor = start
    pauses.sort_by { |p| p[:start] }.each do |p|
      sessions << { start: cursor, end: p[:start] } if p[:start] > cursor
      cursor = p[:end] if p[:end] > cursor
    end
    sessions << { start: cursor, end: finish } if finish > cursor
    sessions
  end
  private_class_method :complement

  # --- kind and review-fix classification: spec D6, D7, rows 1.18-1.20 --------

  def load_graph(dir)
    graph_path = File.join(dir, "graph.md")
    result = with_safe_path(graph_path) { |p| p ? GraphFile.parse(p) : nil }
    edges = result && result[:graph] ? result[:graph][:edges] : {}
    node_ids = result && result[:graph] ? result[:graph][:nodes] : []
    { edges: edges || {}, node_ids: node_ids || [] }
  end
  private_class_method :load_graph

  def resolve_kinds(dir, node_ids)
    graph_ids = node_ids
    kind_of = {}
    source_of = {}
    graph_ids.each do |id|
      kind, source = resolve_kind(dir, id)
      kind_of[id] = kind
      source_of[id] = source
    end
    [kind_of, source_of]
  end
  private_class_method :resolve_kinds

  # Kind comes from the node file when one exists (spec D6, row 1.18);
  # otherwise it falls back to `NodeFile::KIND_PREFIX`, reused rather than
  # restated (row 1.19), and the fallback is flagged.
  def resolve_kind(dir, id)
    path = find_node_file(dir, id)
    if path
      parsed = with_safe_path(path) { |p| NodeFile.parse(p) }
      return [parsed[:kind], :node_file] if parsed && parsed[:kind] && !parsed[:kind].to_s.empty?
    end

    prefix = id.to_s[/\A[a-z]{1,2}/]
    kind = prefix && NodeFile::KIND_PREFIX.invert[prefix]
    [kind, :fallback]
  end
  private_class_method :resolve_kind

  def find_node_file(dir, id)
    Dir.glob(File.join(dir, "nodes", "*.md")).find do |f|
      NodeFile.filename_matches_id?(File.basename(f, ".md"), id)
    end
  end
  private_class_method :find_node_file

  # A review-fix node is a work node that reaches a verify node through
  # `needs` without passing through another verify node, transitively (spec
  # D7, D23, row 1.20): traversal stops expanding past the first verify node
  # on any branch, so a work node several `needs` hops from its nearest
  # verify is still classified a review fix.
  def review_fix?(id, kind_of, edges, memo)
    return memo[id] if memo.key?(id)

    memo[id] = false
    memo[id] = (edges[id] || []).any? do |target|
      kind_of[target] == "verify" || review_fix?(target, kind_of, edges, memo)
    end
  end
  private_class_method :review_fix?

  # --- model, hop: spec rows 1.25, 1.26 -----------------------------------------

  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :present?

  def node_model(attempts)
    attempts.reverse_each do |a|
      model = a[:fields]["model"]
      return model if present?(model)
    end
    :unavailable
  end
  private_class_method :node_model

  # `hop=` unavailable when NO line in the whole ledger ever carries it (a
  # ledger written before the field existed), distinct from a node whose own
  # running line carries no `hop=` in a ledger that does track it elsewhere
  # (hop off, spec row 1.26).
  def node_hop(attempts, hop_ever_seen)
    return :unavailable unless hop_ever_seen

    attempts.reverse_each do |a|
      next unless a[:running_at]

      hop = a[:fields]["hop"]
      return hop.to_i if present?(hop)
      return false
    end
    false
  end
  private_class_method :node_hop

  # --- suite: spec rows 1.21-1.24 -----------------------------------------------

  def parse_suite(raw)
    parts = raw.to_s.split("/")
    case parts.length
    when 4
      { runs: parts[0].to_i, assertions: parts[1].to_i, failures: parts[2].to_i, errors: parts[3].to_i, form: :four_field }
    when 2
      { runs: parts[0].to_i, assertions: :unavailable, failures: parts[1].to_i, errors: :unavailable, form: :two_field }
    else
      { runs: :unavailable, assertions: :unavailable, failures: :unavailable, errors: :unavailable, form: :unknown, raw: raw }
    end
  end
  private_class_method :parse_suite

  # Suite growth is computed against the previous `done` line THAT CARRIES
  # `suite=`, in file order, globally across every subject (spec row 1.24).
  def suite_history(transition_events)
    history = []
    previous = nil
    transition_events.each do |e|
      next unless e[:state] == "done" && !e[:torn]

      suite_raw = e[:fields]["suite"]
      next unless present?(suite_raw)

      parsed = parse_suite(suite_raw)
      growth = previous ? suite_growth(previous, parsed) : :unavailable
      history << { subject: e[:subject], at: parse_time(e[:timestamp]), suite: parsed, growth: growth }
      previous = parsed
    end
    history
  end
  private_class_method :suite_history

  def suite_growth(prev, cur)
    # B1 (v1 review): `runs` used to be a bare subtraction while the other
    # three fields went through `numeric_delta`. A `suite=` value that does
    # not split into 2 or 4 slash-separated parts parses to `form: :unknown`
    # with every field (including `runs`) set to `:unavailable`; subtracting
    # two symbols raised NoMethodError and took the whole `cohorts` verb down
    # with it (reproduced against intent 339's own savepoint.md, whose
    # `suite=` values carry the words "runs" and "assertions" rather than the
    # bare four-slash form `parse_suite` expects).
    growth = { runs: numeric_delta(prev[:runs], cur[:runs]) }
    growth[:failures] = numeric_delta(prev[:failures], cur[:failures])
    growth[:assertions] = numeric_delta(prev[:assertions], cur[:assertions])
    growth[:errors] = numeric_delta(prev[:errors], cur[:errors])
    growth
  end
  private_class_method :suite_growth

  def numeric_delta(prev, cur)
    return :unavailable unless prev.is_a?(Integer) && cur.is_a?(Integer)

    cur - prev
  end
  private_class_method :numeric_delta

  # --- anomalies: spec rows 1.10, 1.11 ------------------------------------------

  def split_anomalies(anomalies)
    torn = anomalies.select { |a| a[:reason].to_s.start_with?("torn:") }
    unattributed = anomalies.select { |a| a[:reason].to_s.start_with?("unattributed") }
    { torn: torn, unattributed: unattributed }
  end
  private_class_method :split_anomalies

  # --- UTF-8 safety for GraphFile and NodeFile: spec row 1.30 -------------------

  # GraphFile.parse and NodeFile.parse read their own path and do not scrub
  # (NodeLedger already does). A bad byte anywhere in graph.md or a node file
  # would otherwise raise out of a regex match deep in either parser. This
  # never writes into intent_dir (spec D2): a scrubbed copy is written to a
  # throwaway Dir.mktmpdir only when the content actually needed scrubbing.
  def with_safe_path(path)
    return yield(nil) unless path && File.exist?(path)

    raw = File.read(path)
    scrubbed = raw.scrub
    return yield(path) if scrubbed == raw

    Dir.mktmpdir("graph-measure-scrub") do |tmp|
      safe_path = File.join(tmp, File.basename(path))
      File.write(safe_path, scrubbed)
      yield(safe_path)
    end
  end
  private_class_method :with_safe_path

  # --- freezing: spec row 1.28 --------------------------------------------------

  def deep_freeze(obj)
    case obj
    when Hash
      obj.each { |k, v| deep_freeze(k); deep_freeze(v) }
    when Array
      obj.each { |v| deep_freeze(v) }
    end
    obj.freeze
  end
  private_class_method :deep_freeze
end
