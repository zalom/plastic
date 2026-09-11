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
    }
  end
  private_class_method :wall_clock_model

  def wall_clock_block(w)
    [
      "== Wall clock ==",
      "delivery total: #{fmt_minutes(w['delivery_total_seconds'])} min (why line to done line)",
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
    return "why line (delivery start)" if clock[:start] && session[:start] == clock[:start]

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
        "fold" => node[:fold],
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
    lines = ["== Nodes ==", "| Node | Kind | Fold | Status | Model | Hop |", "| --- | --- | --- | --- | --- | --- |"]
    nodes.each do |n|
      lines << "| #{n['id']} | #{n['kind']} | #{n['fold']} | #{n['status']} | #{n['model']} | #{n['hop']} |"
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

  # Buckets by node kind (spec's "build, verify, fold" split): a verify node's
  # attempts go to "verify", a folded work node's attempts go to "fold",
  # everything else with a span goes to "build". "lead" is the remainder of
  # active time no attempt's intersected span accounts for (spec's "lead gaps
  # between one terminal line and the next running line"), so the four
  # buckets always sum to active time by construction; row 2.13 states that
  # explicitly rather than leaving it for the reader to add up.
  def buckets_model(record)
    active = record[:active_seconds]
    unless active.is_a?(Numeric)
      return { "build" => UNAVAILABLE, "verify" => UNAVAILABLE, "fold" => UNAVAILABLE, "lead" => UNAVAILABLE,
               "active_seconds" => UNAVAILABLE, "sums_to_active" => false }
    end

    totals = { "build" => 0.0, "verify" => 0.0, "fold" => 0.0 }
    record[:nodes].each_value do |node|
      key = bucket_key(node)
      node[:attempts].each do |a|
        totals[key] += a[:active_span_seconds] if a[:active_span_seconds].is_a?(Numeric)
      end
    end
    accounted = totals.values.sum
    lead = [active - accounted, 0.0].max
    totals["lead"] = lead
    totals["active_seconds"] = active
    totals["sums_to_active"] = (totals["build"] + totals["verify"] + totals["fold"] + lead - active).abs < 0.001
    totals
  end
  private_class_method :buckets_model

  def bucket_key(node)
    return "verify" if node[:kind] == "verify"
    return "fold" if node[:fold]

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
      lines << "fold: #{fmt_minutes(b['fold'])} min"
      lines << "lead: #{fmt_minutes(b['lead'])} min"
      lines << "sum equals active time (#{fmt_minutes(b['active_seconds'])} min): #{b['sums_to_active']}"
    end
    lines
  end
  private_class_method :bucket_block

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
