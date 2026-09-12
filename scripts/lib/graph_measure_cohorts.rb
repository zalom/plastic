# encoding: UTF-8
# frozen_string_literal: true

require "json"
require_relative "node_ledger"
require_relative "graph_measure"
require_relative "graph_measure_models"
require_relative "runner_dispatch"

# GraphMeasureCohorts (intent 343, G10, n6): the second half of the `cohorts`
# verb - approve-then-fix per verify model, hop on versus off, delivery
# latency, the evidence bar, and the two concurrency ceilings. n5's
# GraphMeasureModels owns the model-comparison half of the same verb; this
# module owns everything C33 adds on top of it.
#
# Read-only (spec D2): no lock, no store write, no git working tree opened -
# every metric here is derived from `savepoint.md` alone. It adds no second
# parser and no second per-intent clock: `NodeLedger.entries_from_content`
# (the same reader n5 uses) supplies the raw, file-ordered transition lines
# approve-then-fix needs across every subject, and `GraphMeasure.read` (n1's
# own store walk over a single intent) supplies the clock, the attempts and
# their active spans that latency and the hop comparison need - reusing the
# richest reader this intent already built rather than re-deriving sessions,
# pauses or active-span intersection a second time. The bar section reuses
# `GraphMeasureModels`' own qualified-field counts (`qualified:` is
# injectable so a caller who already has that record never triggers a
# second store walk to get it); only the population loop that drives
# approve-then-fix, hop cohorts, latency and concurrency is this module's
# own, because none of those four are exposed by `GraphMeasureModels`.
#
# `NodeLedger.present?` is `private_class_method` (carried from n1): this
# module keeps its own local copy rather than reopen it, exactly the way
# `GraphMeasureModels` already does for its own `present?` and
# `resolve_kind`.
module GraphMeasureCohorts
  module_function

  SAVEPOINT_FILE = "savepoint.md"
  BAR = 30
  BAR_METRICS = %w[done running_holder model hop].freeze
  BACKGROUND_TEAMS_CEILING =
    "one background delivery team at a time (roadmap prose only; no config source)"
  HOP_FIELD_RE = /\bhop=/.freeze

  # {ok:, approve_then_fix:, hop_cohorts:, latency:, bar:, concurrency:}.
  # `qualified:` lets a caller pass the `qualified` hash a `GraphMeasureModels`
  # read already produced (spec D3/D9: the bar counts against those same
  # per-ledger field counts); when omitted this module reads it itself, once.
  def read(store_dir, now: Time.now, bar: BAR, qualified: nil, project_config: {}, global_config: {})
    dir = File.expand_path(store_dir.to_s)
    qualified ||= GraphMeasureModels.read(dir, project_config: project_config, global_config: global_config)[:qualified]

    approve_acc = {}
    hop_acc = { on: hop_bucket, off: hop_bucket }
    latency_rows = []
    latency_excluded = []
    concurrency_rows = []

    each_child_name(dir).each do |name|
      path = File.join(dir, name)
      next unless File.directory?(path)

      status, content = read_savepoint(path)
      next unless status == :ok

      measure = GraphMeasure.read(path, now: now)
      entries = NodeLedger.entries_from_content(content).reject { |e| e[:torn] }
      # Row 6.12 already excludes an intent with no `Done` line from
      # latency; the same exclusion never reached the hop arms (row 8.13,
      # v1 review M5). A still-open intent's attempts have no known active
      # span (B2), and even after B2 stops fabricating a 0.0 for them, their
      # CLOSED attempts (a failed_verification, say) still counted toward
      # `n` and toward the confound's intent set - inflating a comparison
      # meant to read as "one intent's two delivery phases" into "two
      # intents", silencing `confound_note` exactly when the confound is
      # most real. Reproduced by hand against the real store: before this
      # fix, `graph-measure cohorts` against this very intent's own store
      # printed "confound: (none)" for 340's hop split, because this still-
      # open intent's own hop-tracking attempts were leaking into the "on"
      # arm's intent set; after B2 and this exclusion it correctly names
      # "single intent 340--runner-core-in-session supplies both arms".
      has_done = !!(measure[:clock][:start] && measure[:clock][:end])

      accumulate_approve_then_fix!(entries, measure[:nodes], approve_acc)
      accumulate_hop_cohorts!(name, content, measure[:nodes], hop_acc, has_done)
      accumulate_latency!(name, measure[:clock], measure[:scaffold], latency_rows, latency_excluded)
      accumulate_concurrency!(name, measure[:nodes], now, concurrency_rows)
    end

    record = {
      ok: true,
      approve_then_fix: finalize_approve(approve_acc),
      hop_cohorts: finalize_hop(hop_acc),
      latency: finalize_latency(latency_rows, latency_excluded),
      bar: bar_section(qualified, bar),
      concurrency: finalize_concurrency(concurrency_rows),
    }
    deep_freeze(record)
  end

  # --- rendering ---------------------------------------------------------------

  def render_json(record)
    JSON.generate(model(record))
  end

  def render_text(record)
    lines = []
    lines.concat(approve_block(record[:approve_then_fix]))
    lines << ""
    lines.concat(hop_block(record[:hop_cohorts]))
    lines << ""
    lines.concat(latency_block(record[:latency]))
    lines << ""
    lines.concat(bar_block(record[:bar]))
    lines << ""
    lines.concat(concurrency_block(record[:concurrency]))
    "#{lines.join("\n")}\n"
  end

  def model(record)
    {
      "approve_then_fix" => record[:approve_then_fix].transform_values { |v| approve_row_model(v) },
      "hop_cohorts" => hop_model(record[:hop_cohorts]),
      "latency" => latency_model(record[:latency]),
      "bar" => bar_model(record[:bar]),
      "concurrency" => concurrency_model(record[:concurrency]),
    }
  end

  def approve_row_model(v)
    { "accepted" => v[:accepted], "fixed" => v[:fixed], "rate" => v[:rate] }
  end
  private_class_method :approve_row_model

  def hop_model(h)
    { "on" => arm_model(h[:on]), "off" => arm_model(h[:off]), "confound" => h[:confound] }
  end
  private_class_method :hop_model

  def arm_model(a)
    { "n" => a[:n], "failed_verification_rate" => a[:failed_verification_rate],
      "median_active_span_seconds" => a[:median_active_span_seconds] }
  end
  private_class_method :arm_model

  def latency_model(l)
    {
      "count" => l[:count],
      "median_seconds" => l[:median_seconds],
      "min_seconds" => l[:min_seconds],
      "max_seconds" => l[:max_seconds],
      "rows" => l[:rows].map { |r| latency_row_model(r) },
      "excluded_no_done" => l[:excluded_no_done],
    }
  end
  private_class_method :latency_model

  def latency_row_model(r)
    { "intent" => r[:intent], "anchor" => r[:anchor].to_s, "wall_clock_seconds" => r[:wall_clock_seconds],
      "scaffold_gap_seconds" => r[:scaffold_gap_seconds] }
  end
  private_class_method :latency_row_model

  def bar_model(bar)
    bar.transform_values { |v| v.transform_keys(&:to_s) }
  end
  private_class_method :bar_model

  def concurrency_model(c)
    {
      "dispatch_ceiling" => c[:dispatch_ceiling],
      "background_teams_ceiling" => c[:background_teams_ceiling],
      "observed" => c[:observed].map { |r| { "intent" => r[:intent], "max_simultaneous_running" => r[:max_simultaneous_running] } },
    }
  end
  private_class_method :concurrency_model

  def approve_block(by_model)
    lines = ["== Approve-then-fix =="]
    if by_model.empty?
      lines << "(no verify verdicts recorded)"
      return lines
    end

    by_model.each do |m, v|
      lines << "#{m}: #{v[:fixed]}/#{v[:accepted]} accepted verdicts followed by later work (n=#{v[:accepted]}), " \
               "rate #{rate_text(v[:rate])}"
    end
    lines
  end
  private_class_method :approve_block

  def hop_block(h)
    lines = ["== Hop cohorts =="]
    lines << "hop on: n=#{h[:on][:n]} failed_verification_rate=#{rate_text(h[:on][:failed_verification_rate])} " \
             "median_active_span=#{span_minutes_text(h[:on][:median_active_span_seconds])}"
    lines << "hop off: n=#{h[:off][:n]} failed_verification_rate=#{rate_text(h[:off][:failed_verification_rate])} " \
             "median_active_span=#{span_minutes_text(h[:off][:median_active_span_seconds])}"
    lines << "confound: #{h[:confound] || '(none)'}"
    lines
  end
  private_class_method :hop_block

  def latency_block(l)
    lines = ["== Delivery latency =="]
    lines << "qualified intents: #{l[:count]}"
    lines << "median: #{span_hours_text(l[:median_seconds])}"
    lines << "min: #{span_hours_text(l[:min_seconds])}"
    lines << "max: #{span_hours_text(l[:max_seconds])}"
    lines << "excluded (no Done line): #{l[:excluded_no_done].empty? ? '(none)' : l[:excluded_no_done].join(', ')}"
    l[:rows].each do |r|
      lines << "  #{r[:intent]}: #{span_hours_text(r[:wall_clock_seconds])} " \
               "(anchor=#{r[:anchor]}, scaffold_gap=#{span_hours_text(r[:scaffold_gap_seconds])})"
    end
    lines
  end
  private_class_method :latency_block

  def bar_block(bar)
    lines = ["== Evidence bar (#{BAR} qualified deliveries per metric) =="]
    bar.each do |metric, v|
      lines << "#{metric}: #{v[:qualified]} qualified against a bar of #{v[:bar]} (shortfall #{v[:shortfall]})"
    end
    lines
  end
  private_class_method :bar_block

  def concurrency_block(c)
    lines = ["== Concurrency =="]
    lines << "per-intent dispatch ceiling: RunnerDispatch::DEFAULT_LIMIT = #{c[:dispatch_ceiling]}"
    lines << "background-agent ceiling: #{c[:background_teams_ceiling]}"
    c[:observed].each { |r| lines << "  #{r[:intent]}: max simultaneous running = #{r[:max_simultaneous_running]}" }
    lines
  end
  private_class_method :concurrency_block

  def rate_text(r)
    r == :unavailable ? "unavailable" : format("%.1f%%", r * 100)
  end
  private_class_method :rate_text

  def span_minutes_text(s)
    s == :unavailable ? "unavailable" : format("%.1f min", s / 60.0)
  end
  private_class_method :span_minutes_text

  def span_hours_text(s)
    (s.nil? || s == :unavailable) ? "unavailable" : format("%.2fh", s / 3600.0)
  end
  private_class_method :span_hours_text

  # --- the store walk (own copy: GraphMeasureModels' equivalent is private) ----

  def each_child_name(dir)
    return [] unless File.directory?(dir)

    Dir.children(dir).reject { |e| e.start_with?(".") }.sort
  rescue Errno::EACCES, Errno::ENOENT
    []
  end
  private_class_method :each_child_name

  def read_savepoint(intent_dir)
    content = File.read(File.join(intent_dir, SAVEPOINT_FILE))
    [:ok, content.scrub]
  rescue Errno::ENOENT
    [:missing, nil]
  rescue Errno::EACCES
    [:unreadable, nil]
  end
  private_class_method :read_savepoint

  # --- approve-then-fix: spec rows 6.1-6.6 --------------------------------------

  # `entries` is the full, file-ordered, non-torn transition-line list for
  # ONE intent (every subject interleaved, spec row 6.2's "transition lines
  # only" - a Commit line, a Lock takeover line, and every stage line are
  # never transition candidates and never reach this list at all). A verify
  # node's `done` line with `verdict=accept` is "fixed" when ANY later line
  # in this same file-ordered list, regardless of its own timestamp (row
  # 6.4), belongs to a work-kind subject.
  def accumulate_approve_then_fix!(entries, nodes, acc)
    entries.each_with_index do |e, i|
      next unless e[:state] == "done"

      kind = nodes.dig(e[:subject], :kind)
      next unless kind == "verify"

      model = nodes.dig(e[:subject], :model)
      model_key = present?(model) ? model.to_s : "unavailable"
      bucket = (acc[model_key] ||= { accepted: 0, fixed: 0 })

      next unless e[:fields]["verdict"] == "accept"

      bucket[:accepted] += 1
      followed = entries[(i + 1)..].any? { |later| nodes.dig(later[:subject], :kind) == "work" }
      bucket[:fixed] += 1 if followed
    end
  end
  private_class_method :accumulate_approve_then_fix!

  def finalize_approve(acc)
    acc.transform_values do |b|
      rate = b[:accepted].zero? ? :unavailable : (b[:fixed].to_f / b[:accepted])
      { accepted: b[:accepted], fixed: b[:fixed], rate: rate }
    end
  end
  private_class_method :finalize_approve

  # --- hop cohorts: spec rows 6.7-6.10 ------------------------------------------

  def hop_bucket
    { count: 0, failed: 0, spans: [], intents: [] }
  end
  private_class_method :hop_bucket

  # A ledger that never once writes `hop=` contributes to NEITHER arm (spec
  # row 6.8): it is unavailable evidence, not a hop-off data point. Every
  # CLOSED attempt (any terminal state) in a ledger that does track hop=
  # goes to the "on" arm when ITS OWN running line carried `hop=` (spec row
  # 6.7: split per attempt, never per node) and to "off" otherwise.
  def accumulate_hop_cohorts!(name, content, nodes, hop_acc, has_done)
    return unless has_done
    return unless content.match?(HOP_FIELD_RE)

    nodes.each_value do |node|
      Array(node[:attempts]).each do |attempt|
        next unless attempt[:terminal_state]

        arm = present?(attempt[:fields]["hop"]) ? :on : :off
        bucket = hop_acc[arm]
        bucket[:count] += 1
        bucket[:failed] += 1 if attempt[:terminal_state] == "failed_verification"
        bucket[:spans] << attempt[:active_span_seconds] if attempt[:active_span_seconds]
        bucket[:intents] << name
      end
    end
  end
  private_class_method :accumulate_hop_cohorts!

  def finalize_hop(hop_acc)
    {
      on: arm_summary(hop_acc[:on]),
      off: arm_summary(hop_acc[:off]),
      confound: confound_note(hop_acc[:on][:intents], hop_acc[:off][:intents]),
    }
  end
  private_class_method :finalize_hop

  def arm_summary(bucket)
    n = bucket[:count]
    return { n: 0, failed_verification_rate: :unavailable, median_active_span_seconds: :unavailable } if n.zero?

    { n: n, failed_verification_rate: bucket[:failed].to_f / n, median_active_span_seconds: median(bucket[:spans]) }
  end
  private_class_method :arm_summary

  # Named only when both arms are non-empty and drawn from exactly the same
  # single intent (spec row 6.10): the hop split then coincides with that
  # one intent's own delivery phases, not an independent variable.
  def confound_note(on_intents, off_intents)
    return nil if on_intents.empty? || off_intents.empty?

    all = (on_intents + off_intents).uniq
    return nil unless all.length == 1

    "single intent #{all.first} supplies both arms; the hop split follows that intent's delivery phases, " \
      "not an independent variable"
  end
  private_class_method :confound_note

  # --- delivery latency: spec rows 6.11-6.13 ------------------------------------

  # Reuses GraphMeasure's own clock (D20's Why-anchor, falling back to the
  # first ledger line, never presented as Why-anchored when it is not) -
  # this module computes no anchor of its own. An intent with no `Done`
  # line at all has no clock end and is excluded and named (row 6.12), never
  # left to grow with the wall clock.
  def accumulate_latency!(name, clock, scaffold, rows, excluded)
    unless clock[:start] && clock[:end]
      excluded << name
      return
    end

    rows << {
      intent: name,
      anchor: clock[:anchor],
      wall_clock_seconds: clock[:wall_clock_seconds],
      scaffold_gap_seconds: scaffold && scaffold[:gap_seconds],
    }
  end
  private_class_method :accumulate_latency!

  def finalize_latency(rows, excluded)
    seconds = rows.map { |r| r[:wall_clock_seconds] }
    {
      count: rows.length,
      median_seconds: median(seconds),
      min_seconds: seconds.min || :unavailable,
      max_seconds: seconds.max || :unavailable,
      rows: rows,
      excluded_no_done: excluded,
    }
  end
  private_class_method :finalize_latency

  # --- the evidence bar: spec rows 6.14-6.17 ------------------------------------

  # Never a recommendation, at any qualified count (spec D9, rows 6.16,
  # 6.17): the record carries only qualified/bar/shortfall/met, nothing this
  # module or its renderers could ever read as "raise the ceiling".
  def bar_section(qualified, bar)
    BAR_METRICS.each_with_object({}) do |metric, memo|
      n = qualified[metric.to_sym].to_i
      memo[metric] = { qualified: n, bar: bar, shortfall: [bar - n, 0].max, met: n >= bar }
    end
  end
  private_class_method :bar_section

  # --- concurrency: spec rows 6.18-6.19 -----------------------------------------

  # Every attempt that ever opened a `running` line, in this one intent,
  # regardless of kind or completion. An attempt still open at `now` runs
  # through `now` (the same convention GraphMeasure's own interval merge
  # uses) so a live dispatch still counts toward the overlap.
  def accumulate_concurrency!(name, nodes, now, rows)
    intervals = nodes.values.flat_map { |n| Array(n[:attempts]) }.filter_map do |a|
      next nil unless a[:running_at]

      { start: a[:running_at], end: a[:terminal_at] || now }
    end
    rows << { intent: name, max_simultaneous_running: intervals.empty? ? :unavailable : max_overlap(intervals) }
  end
  private_class_method :accumulate_concurrency!

  # A sweep over interval start (+1) and end (-1) events, sorted by time and
  # then by delta ascending, so an end processed at the exact same instant
  # as another interval's start closes first: two attempts that merely hand
  # off at one timestamp are never counted as briefly simultaneous.
  def max_overlap(intervals)
    events = intervals.flat_map { |iv| [[iv[:start], 1], [iv[:end], -1]] }
    events.sort_by! { |(t, delta)| [t, delta] }
    current = 0
    peak = 0
    events.each do |(_t, delta)|
      current += delta
      peak = current if current > peak
    end
    peak
  end
  private_class_method :max_overlap

  def finalize_concurrency(rows)
    { dispatch_ceiling: RunnerDispatch::DEFAULT_LIMIT, background_teams_ceiling: BACKGROUND_TEAMS_CEILING, observed: rows }
  end
  private_class_method :finalize_concurrency

  # --- shared helpers ------------------------------------------------------------

  def median(values)
    return :unavailable if values.empty?

    sorted = values.sort
    mid = sorted.length / 2
    sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
  private_class_method :median

  # NodeLedger.present? is private_class_method (carried from n1): local
  # equivalent, not a reopen.
  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :present?

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
