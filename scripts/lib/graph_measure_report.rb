# encoding: UTF-8
# frozen_string_literal: true

require "json"

# GraphMeasureReport (intent 343, G10, n2): turns one `GraphMeasure.read`
# record into two renderings, text and JSON, that carry exactly the same
# numbers because both read the one `model(record)` hash and neither
# recomputes anything (spec D12, matrix row 2.18).
#
# Every leaf in `model` is JSON-safe already: a Time becomes an ISO-8601
# string, a missing or `:unavailable` measure becomes the literal string
# "unavailable" (spec D3, row 2.12), never blank and never zero. `render_text`
# only formats what `model` already computed; it never looks at the raw
# `GraphMeasure` record.
module GraphMeasureReport
  module_function

  UNAVAILABLE = "unavailable"

  # Markdown table cells cap a comment at this many characters (row 2.16): a
  # very long comment is truncated with a trailing ellipsis rather than
  # producing one unwrapped line.
  COMMENT_CAP = 200

  # --- public entry points -----------------------------------------------------

  def render_json(record)
    JSON.generate(model(record))
  end

  def render_text(record)
    m = model(record)
    lines = []
    lines.concat(wall_clock_block(m[:wall_clock]))
    lines << ""
    lines.concat(session_block(m[:sessions]))
    lines << ""
    lines.concat(node_block(m[:nodes]))
    lines << ""
    lines.concat(bucket_block(m[:buckets]))
    lines << ""
    lines.concat(verify_cost_block(m[:verify_cost]))
    lines << ""
    lines.concat(anomaly_block(m[:anomalies]))
    "#{lines.join("\n")}\n"
  end

  # The one shared model both renderers read (row 2.18). Every value is a
  # String, Numeric, true/false, an Array, or a Hash: never a raw Time, never
  # a bare `:unavailable` symbol, never nil.
  def model(record)
    {
      wall_clock: wall_clock_model(record),
      sessions: sessions_model(record),
      nodes: nodes_model(record),
      buckets: buckets_model(record),
      verify_cost: verify_cost_model(record),
      anomalies: anomalies_model(record),
    }
  end

  # --- wall clock: spec D5, matrix row 2.7 -------------------------------------

  def wall_clock_model(record)
    clock = record[:clock]
    scaffold = record[:scaffold]
    {
      "delivery_total_seconds" => av_seconds(clock[:wall_clock_seconds]),
      "active_seconds" => av_seconds(record[:active_seconds]),
      "paused_seconds" => av_seconds(record[:paused_seconds]),
      "scaffold_gap_seconds" => av_seconds(scaffold[:gap_seconds]),
      "what_at" => av_time(scaffold[:what_at]),
      "why_at" => av_time(scaffold[:why_at]),
      "done_at" => av_time(clock[:end]),
      # D20: "why" when the clock anchors on the ledger's own `Why` line,
      # "first_line" when it fell back to the first ledger line because no
      # `Why` line exists at all (row 3.23). Never nil: build_clock always
      # sets one of the two.
      "clock_anchor" => clock[:anchor].to_s,
    }
  end
  private_class_method :wall_clock_model

  def wall_clock_block(w)
    anchor_label = w["clock_anchor"] == "first_line" ? "first ledger line" : "why line"
    [
      "== Wall clock ==",
      "clock anchor: #{anchor_label}" \
      "#{w['clock_anchor'] == 'first_line' ? ' (no Why line in this ledger, D20 fallback)' : ''}",
      "delivery total: #{fmt_minutes(w['delivery_total_seconds'])} min (#{anchor_label} to done line)",
      "active: #{fmt_minutes(w['active_seconds'])} min",
      "paused: #{fmt_minutes(w['paused_seconds'])} min",
      "scaffold gap (what line to why line, not counted in delivery total): " \
      "#{fmt_minutes(w['scaffold_gap_seconds'])} min",
    ]
  end
  private_class_method :wall_clock_block

  # --- sessions: spec D5.3, matrix row 2.8 -------------------------------------

  def sessions_model(record)
    clock = record[:clock]
    pauses = record[:pauses]
    record[:sessions].each_with_index.map do |s, i|
      {
        "index" => i + 1,
        "start" => av_time(s[:start]),
        "end" => av_time(s[:end]),
        "duration_seconds" => av_seconds(s[:end] - s[:start]),
        "start_evidence" => session_start_evidence(s, pauses, clock),
        "end_evidence" => session_end_evidence(s, pauses, clock),
      }
    end
  end
  private_class_method :sessions_model

  # A session's start is bounded either by the delivery clock's own start
  # (the first `Why` line) or by the pause immediately before it, named by
  # what CLOSED that pause (spec D5.3: `Lock takeover:` or the line after a
  # `PAUSED` report). Matched by timestamp equality against `record[:pauses]`
  # rather than by array index, because `complement` skips a zero-length
  # session at either end (row 2.8).
  def session_start_evidence(session, pauses, clock)
    if clock[:start] && session[:start] == clock[:start]
      return clock[:anchor] == :first_line ? "first ledger line (delivery start, no Why line)" : "why line (delivery start)"
    end

    closing = pauses.find { |p| p[:end] == session[:start] }
    return "pause closed by #{closing[:closed_by]}" if closing

    UNAVAILABLE
  end
  private_class_method :session_start_evidence

  def session_end_evidence(session, pauses, clock)
    return "done line (delivery end)" if clock[:end] && session[:end] == clock[:end]

    opening = pauses.find { |p| p[:start] == session[:end] }
    return "pause opened by #{opening[:opened_by]}" if opening

    UNAVAILABLE
  end
  private_class_method :session_end_evidence

  def session_block(sessions)
    lines = ["== Sessions ==", "| # | Start | End | Duration (min) | Start evidence | End evidence |",
             "| --- | --- | --- | --- | --- | --- |"]
    if sessions.empty?
      lines << "(none)"
    else
      sessions.each do |s|
        lines << "| #{s['index']} | #{s['start']} | #{s['end']} | #{fmt_minutes(s['duration_seconds'])} | " \
                 "#{s['start_evidence']} | #{s['end_evidence']} |"
      end
    end
    lines
  end
  private_class_method :session_block

  # --- nodes: spec D6/D7, matrix rows 2.9-2.12, 2.15, 2.16 ---------------------

  def nodes_model(record)
    sort_ids(record[:nodes].keys).map do |id|
      node = record[:nodes][id]
      {
        "id" => id,
        "kind" => av(node[:kind]),
        "kind_source" => av(node[:kind_source] && node[:kind_source].to_s),
        "review_fix" => node[:review_fix],
        "status" => av(node[:status]),
        "model" => av(node[:model]),
        "hop" => node[:hop] == false ? false : av(node[:hop]),
        "attempts" => node[:attempts].map { |a| attempt_model(a) },
      }
    end
  end
  private_class_method :nodes_model

  def attempt_model(a)
    {
      "holder" => av(a[:holder]),
      "terminal_state" => av(a[:terminal_state]),
      "running_open" => a[:running_open],
      "raw_span_seconds" => av_seconds(a[:raw_span_seconds]),
      "active_span_seconds" => av_seconds(a[:active_span_seconds]),
      "suite" => suite_model(a[:suite]),
      "comment" => sanitize_comment(a[:comment]),
    }
  end
  private_class_method :attempt_model

  def suite_model(suite)
    return UNAVAILABLE unless suite.is_a?(Hash)

    {
      "runs" => av(suite[:runs]),
      "assertions" => av(suite[:assertions]),
      "failures" => av(suite[:failures]),
      "errors" => av(suite[:errors]),
    }
  end
  private_class_method :suite_model

  # A pipe in a comment would otherwise split a markdown table row into extra
  # columns (row 2.15); a very long comment is capped rather than left as one
  # unwrapped line (row 2.16).
  def sanitize_comment(comment)
    return UNAVAILABLE unless comment && !comment.to_s.strip.empty?

    text = comment.to_s.gsub("|", "/")
    return text if text.length <= COMMENT_CAP

    "#{text[0...(COMMENT_CAP - 3)].rstrip}..."
  end
  private_class_method :sanitize_comment

  def node_block(nodes)
    lines = ["== Nodes ==", "| Node | Kind | Review fix | Status | Model | Hop |",
             "| --- | --- | --- | --- | --- | --- |"]
    nodes.each do |n|
      lines << "| #{n['id']} | #{n['kind']} | #{n['review_fix']} | #{n['status']} | #{n['model']} | #{n['hop']} |"
      next if n["attempts"].empty?

      lines << "  | Attempt | Holder | Terminal | Raw (min) | Active (min) | Comment |"
      lines << "  | --- | --- | --- | --- | --- | --- |"
      n["attempts"].each_with_index do |a, i|
        lines << "  | #{i + 1} | #{a['holder']} | #{a['terminal_state']} | " \
                 "#{fmt_minutes(a['raw_span_seconds'])} | #{fmt_minutes(a['active_span_seconds'])} | #{a['comment']} |"
      end
    end
    lines
  end
  private_class_method :node_block

  # --- buckets: spec D17, matrix row 2.13 --------------------------------------

  # Buckets by node kind (spec's "build, verify, review fix" split): a
  # verify node's attempts go to "verify", a review-fix work node's
  # attempts go to "review_fix", everything else with a span goes to
  # "build". "lead" is the remainder of active time no attempt's
  # intersected span accounts for (spec's "lead gaps between one terminal
  # line and the next running line"), so the four buckets always sum to
  # active time by construction; row 2.13 states that explicitly rather
  # than leaving it for the reader to add up.
  # B3 (v1 review): the three gate buckets seeded at 0.0 and never fell back
  # to UNAVAILABLE, so a ledger where NO attempt in a bucket ever carries a
  # measured span (337, which has no `running` line anywhere) rendered
  # "build: 0.0 / verify: 0.0 / review_fix: 0.0", indistinguishable from
  # "measured and genuinely zero", six lines above `== Verify cost ==`
  # correctly printing "unavailable" for the same absent source. Reproduced
  # by hand: `graph-measure intent test/fixtures/ledgers/337--roadmap-graph`
  # prints exactly that shape. `contributed` tracks whether at least one
  # attempt actually reached a bucket; the running sum (`sums`) still
  # starts at 0.0 for the arithmetic `lead`/`sums_to_active` need, but the
  # RENDERED value for a bucket nothing contributed to is UNAVAILABLE,
  # never the seed.
  #
  # NEW-3 (v2 review): `contributed` could only say "nothing landed here",
  # never distinguish WHY - a bucket with no node of its kind in this intent
  # at all (a real zero: there was never anything to measure) rendered the
  # same UNAVAILABLE as a bucket whose nodes exist but never carried a
  # measured span (unmeasurable, not absent). Reproduced by hand against a
  # hermetic one-node work-only intent: "build: 30.0 / verify: unavailable
  # / review_fix: unavailable" though the intent has no verify node and no
  # review-fix node anywhere, which the report's own node table already
  # proves. `has_kind` now tracks whether ANY node of a bucket's kind
  # exists at all; a bucket with no node of its kind renders 0.0 (a real,
  # checkable zero), and only a bucket whose nodes exist but never
  # contributed a measured span renders UNAVAILABLE.
  def buckets_model(record)
    active = record[:active_seconds]
    unless active.is_a?(Numeric)
      return { "build" => UNAVAILABLE, "verify" => UNAVAILABLE, "review_fix" => UNAVAILABLE, "lead" => UNAVAILABLE,
               "active_seconds" => UNAVAILABLE, "sums_to_active" => false }
    end

    sums = { "build" => 0.0, "verify" => 0.0, "review_fix" => 0.0 }
    has_kind = { "build" => false, "verify" => false, "review_fix" => false }
    contributed = { "build" => false, "verify" => false, "review_fix" => false }
    record[:nodes].each_value do |node|
      key = bucket_key(node)
      has_kind[key] = true
      node[:attempts].each do |a|
        next unless a[:active_span_seconds].is_a?(Numeric)

        sums[key] += a[:active_span_seconds]
        contributed[key] = true
      end
    end
    accounted = sums.values.sum
    lead = [active - accounted, 0.0].max
    sums_to_active = (sums["build"] + sums["verify"] + sums["review_fix"] + lead - active).abs < 0.001

    totals = {}
    %w[build verify review_fix].each do |key|
      totals[key] = if contributed[key]
                      sums[key]
                    elsif has_kind[key]
                      UNAVAILABLE
                    else
                      0.0
                    end
    end
    totals["lead"] = lead
    totals["active_seconds"] = active
    totals["sums_to_active"] = sums_to_active
    totals
  end
  private_class_method :buckets_model

  def bucket_key(node)
    return "verify" if node[:kind] == "verify"
    return "review_fix" if node[:review_fix]

    "build"
  end
  private_class_method :bucket_key

  def bucket_block(b)
    lines = ["== Buckets (sum to active time) =="]
    if b["active_seconds"] == UNAVAILABLE
      lines << UNAVAILABLE
    else
      lines << "build: #{fmt_minutes(b['build'])} min"
      lines << "verify: #{fmt_minutes(b['verify'])} min"
      lines << "review fix: #{fmt_minutes(b['review_fix'])} min"
      lines << "lead: #{fmt_minutes(b['lead'])} min"
      lines << "sum equals active time (#{fmt_minutes(b['active_seconds'])} min): #{b['sums_to_active']}"
    end
    lines
  end
  private_class_method :bucket_block

  # --- verify cost: intent 343 (G10, n4), matrix rows 4.12-4.14 ----------------

  # The verify nodes' total active span and its share of active time: the
  # same per-attempt `active_span_seconds` the buckets above sum, but
  # reported `unavailable` rather than 0.0 when NOT ONE verify-kind node's
  # attempt carries a `running` line at all (row 4.13) - a ledger predating
  # the `running` line convention has no verify spans to sum, and 0.0 would
  # read as "verification is free" rather than "unmeasurable from this
  # ledger" (spec D3).
  #
  # B3 second hole (v1 review): `a[:running_at]` alone is satisfied by an
  # OPEN attempt too (running, not yet terminal), so a verify node still
  # mid-review reported "total active span: 0.0 min" - measured and zero -
  # rather than "unavailable" - not yet measurable. Reproduced with a single
  # verify node whose only attempt is an open `running` line inside an
  # otherwise-closed clock: `has_running` was `true` (the open attempt has a
  # `running_at`) so the guard let a real `sum_active_spans` call through,
  # and that sum is 0.0 over an attempt with no `span_seconds` yet. A span
  # is only measured once an attempt has CLOSED (spec row 1.4-1.9's own
  # running-to-terminal pairing), so the guard checks `terminal_at` too.
  #
  # NEW-1 (v2 review): checking `running_at && terminal_at` alone is still
  # not "a span was measured" - it is only "the attempt itself closed". Once
  # the open-clock fix left EVERY attempt's `active_span_seconds` nil while
  # the delivery clock has no end yet, a closed verify attempt inside that
  # open clock still satisfied this guard, and `sum_active_spans` coerced
  # its nil span to 0.0. Reproduced by hand: a hermetic intent with one
  # verify node, one closed attempt spanning a real hour, and no `Done`
  # stage line printed "active: unavailable" at the top of the clock block
  # and "total active span: 0.0 min" in Verify cost a few lines later. The
  # guard now requires an actual numeric `active_span_seconds` on at least
  # one attempt, never merely a closed one.
  def verify_cost_model(record)
    verify_nodes = record[:nodes].select { |_, n| n[:kind] == "verify" }
    all_attempts = verify_nodes.values.flat_map { |n| n[:attempts] }
    has_measured = all_attempts.any? { |a| measured_span?(a) }
    active = record[:active_seconds]

    total = has_measured ? sum_active_spans(all_attempts) : nil
    share = (total && active.is_a?(Numeric) && active.positive?) ? total / active : nil

    {
      "total_active_span_seconds" => av_seconds(total),
      "share_of_active_time" => av_seconds(share),
      "nodes" => sort_ids(verify_nodes.keys).map { |id| verify_node_model(id, verify_nodes[id]) },
    }
  end
  private_class_method :verify_cost_model

  def verify_node_model(id, node)
    attempts = node[:attempts]
    node_total = attempts.any? { |a| measured_span?(a) } ? sum_active_spans(attempts) : nil
    {
      "id" => id,
      "active_span_seconds" => av_seconds(node_total),
      "verdict" => av(verdict_for(attempts)),
    }
  end
  private_class_method :verify_node_model

  # An attempt is closed (running_at and terminal_at both present) AND its
  # own active span actually resolved to a number, never merely nil because
  # the delivery clock itself has no end yet (NEW-1).
  def measured_span?(a)
    a[:running_at] && a[:terminal_at] && a[:active_span_seconds].is_a?(Numeric)
  end
  private_class_method :measured_span?

  def sum_active_spans(attempts)
    attempts.sum { |a| a[:active_span_seconds].is_a?(Numeric) ? a[:active_span_seconds] : 0.0 }
  end
  private_class_method :sum_active_spans

  # The last (file-order) attempt whose fields carry a `verdict=` (row
  # 4.14): a review's verdict is shown beside its cost even when the cost
  # itself is unavailable, mirroring `GraphMeasure`'s own "most recent field
  # wins" reading of `model=`.
  def verdict_for(attempts)
    attempts.reverse_each do |a|
      verdict = a[:fields]["verdict"]
      return verdict if verdict && !verdict.to_s.strip.empty?
    end
    nil
  end
  private_class_method :verdict_for

  def verify_cost_block(vc)
    lines = ["== Verify cost =="]
    lines << "total active span: #{fmt_minutes(vc['total_active_span_seconds'])} min"
    lines << "share of active time: #{fmt_percent(vc['share_of_active_time'])}"
    if vc["nodes"].empty?
      lines << "(no verify nodes)"
    else
      lines << "| Verify node | Active (min) | Verdict |"
      lines << "| --- | --- | --- |"
      vc["nodes"].each do |n|
        lines << "| #{n['id']} | #{fmt_minutes(n['active_span_seconds'])} | #{n['verdict']} |"
      end
    end
    lines
  end
  private_class_method :verify_cost_block

  # --- anomalies: spec D4, matrix row 2.14 -------------------------------------

  def anomalies_model(record)
    {
      "torn" => record[:anomalies][:torn].map { |a| a[:line] },
      "unattributed" => record[:anomalies][:unattributed].map { |a| a[:line] },
    }
  end
  private_class_method :anomalies_model

  def anomaly_block(a)
    lines = ["== Anomalies =="]
    if a["torn"].empty? && a["unattributed"].empty?
      lines << "(none)"
    else
      a["torn"].each { |raw| lines << "torn: #{raw}" }
      a["unattributed"].each { |raw| lines << "unattributed: #{raw}" }
    end
    lines
  end
  private_class_method :anomaly_block

  # --- formatting helpers -------------------------------------------------------

  # A missing or explicitly `:unavailable` measure renders as the literal
  # string "unavailable" (spec D3, row 2.12), never blank and never zero.
  # `false` is a real measured value (hop off) and passes through untouched.
  def av(value)
    return UNAVAILABLE if value.nil? || value == :unavailable

    value
  end
  private_class_method :av

  def av_time(value)
    return UNAVAILABLE unless value.is_a?(Time)

    value.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end
  private_class_method :av_time

  def av_seconds(value)
    return UNAVAILABLE unless value.is_a?(Numeric)

    value
  end
  private_class_method :av_seconds

  def fmt_minutes(seconds)
    return UNAVAILABLE unless seconds.is_a?(Numeric)

    format("%.1f", seconds / 60.0)
  end
  private_class_method :fmt_minutes

  def fmt_percent(ratio)
    return UNAVAILABLE unless ratio.is_a?(Numeric)

    format("%.1f%%", ratio * 100)
  end
  private_class_method :fmt_percent

  # Numeric-aware id sort ("n2" before "n10"), the same shape
  # scripts/lib/outcome_report.rb's sort_ids uses.
  def sort_ids(ids)
    ids.sort_by do |id|
      m = id.to_s.match(/\A([A-Za-z]+)(\d+)\z/)
      m ? [m[1], m[2].to_i] : [id.to_s, 0]
    end
  end
  private_class_method :sort_ids
end
