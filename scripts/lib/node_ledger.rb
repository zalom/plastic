# encoding: UTF-8
# frozen_string_literal: true

require "strscan"
require_relative "savepoint"
require_relative "guarded_append"

# NodeLedger - the node and intent transition line (intent 335, G2). Owns the
# line's byte-exact format, the closed state vocabulary, the required fields per
# state, the parser, torn-line and unattributed-line detection, status as the
# last line per subject in file order, and the guarded transition append that
# skips dedup entirely (spec D11).
#
# Per spec D17 the subject vocabulary (`Savepoint::INTENT_SUBJECT`,
# `Savepoint::NODE_SUBJECT_RE`, `Savepoint.transition_candidate?`) lives on
# Savepoint, not here: this file requires savepoint.rb and reuses them, the
# dependency running one way only (test/savepoint_split_test.rb:57 pins
# savepoint.rb to loading no other project file).
#
# Pure and dependency-injected: every path and clock is an argument, `guard:` is
# an injectable seam for the transition append, and this module reads no
# environment variable.
module NodeLedger
  module_function

  # Ten states, closed (spec D1). "ready" is computed and never written.
  STATES = %w[
    planned running done failed_verification needs_decision blocked deferred
    superseded abandoned reclaimed
  ].freeze

  # A written state's RESOLVED state for the ready function 336 builds on top of
  # this ledger (spec D2): every state resolves to itself except `reclaimed`,
  # which resolves to `planned` ("a reclaimed node is planned again").
  RESOLUTION = { "reclaimed" => "planned" }.freeze

  # Required fields per state (spec D4), refused by #append_transition and read
  # as torn by #torn? when absent. `done`'s evidence requirement (gates= plus at
  # least one of commit=/verdict=) is asymmetric, so it is not representable as
  # a flat list; DONE_EVIDENCE_FIELDS below carries the "at least one of" half.
  REQUIRED_FIELDS = {
    "planned" => [],
    "running" => %w[holder expires packet model],
    "done" => %w[gates],
    "failed_verification" => %w[gates reason],
    "needs_decision" => %w[question],
    "blocked" => %w[reason],
    "deferred" => %w[reason],
    "superseded" => %w[by],
    "abandoned" => %w[reason],
    "reclaimed" => %w[holder expired],
  }.freeze

  # `done` requires gates= plus at least one of these (spec D7). `model=` is
  # deliberately absent from every required-fields list except `running` (spec
  # D6) and is accepted, never required, everywhere else - no separate table
  # entry is needed for that: an unlisted field is never required.
  DONE_EVIDENCE_FIELDS = %w[commit verdict].freeze

  # Canonical field render order (spec D8's "stable declared order", matrix
  # 2.6): every key named in REQUIRED_FIELDS or DONE_EVIDENCE_FIELDS, plus
  # `model` (accepted on any state). A field outside this list still renders,
  # sorted after these, so an unrecognized key is never silently dropped.
  FIELD_ORDER = %w[holder expires packet model gates commit verdict reason question by expired].freeze

  SEPARATOR = "  "

  # timestamp<SEP>subject<SEP>state field=value... (comment). Two-space
  # separators keep the line a three-field line under both `split(/\s{2,}/)`
  # and every reader's own `SAVEPOINT_RE` (spec "Line shape"). Raises
  # ArgumentError, writing nothing, for an unknown state or a missing required
  # field (D4/D9): the caller of #append_transition relies on this check
  # running BEFORE the file is ever touched.
  def transition_line(subject:, state:, fields: {}, comment: nil, now: Time.now)
    state = state.to_s
    raise ArgumentError, "unknown transition state: #{state.inspect}" unless STATES.include?(state)

    missing = missing_fields(state, fields)
    raise ArgumentError, "state #{state} requires #{missing.join(', ')}" if missing.any?

    timestamp = now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    rest = ([state] + render_fields(fields)).join(" ")
    rest = "#{rest} (#{normalize_value(comment)})" if comment && !comment.to_s.strip.empty?
    "#{timestamp}#{SEPARATOR}#{subject}#{SEPARATOR}#{rest}\n"
  end

  # Collapse every run of two-or-more spaces in `text` to one (spec "Line
  # shape"), so a caller-supplied value or comment can never reintroduce the
  # double-space the line's own separators rely on. A tab or a newline is
  # refused outright (raises ArgumentError) rather than collapsed: silently
  # eating either would hide a value that could otherwise tear a ledger line.
  def normalize_value(text)
    value = text.to_s
    raise ArgumentError, "value must not contain a tab or a newline: #{value.inspect}" if value =~ /[\t\n]/

    value.gsub(/ {2,}/, " ")
  end

  # A required-field D4 check independent of vocabulary validity: given a state
  # (assumed valid) and a fields hash, the list of required field names still
  # missing. `done`'s "at least one of commit=/verdict=" half renders as the
  # literal string "commit or verdict" when both are absent.
  def missing_fields(state, fields)
    normalized = stringify_keys(fields)
    required = REQUIRED_FIELDS.fetch(state.to_s, [])
    missing = required.reject { |key| present?(normalized[key]) }
    if state.to_s == "done" && DONE_EVIDENCE_FIELDS.none? { |key| present?(normalized[key]) }
      missing += ["commit or verdict"]
    end
    missing
  end

  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :present?

  def stringify_keys(fields)
    (fields || {}).each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
  end
  private_class_method :stringify_keys

  def render_fields(fields)
    normalized = stringify_keys(fields)
    known = FIELD_ORDER.select { |key| normalized.key?(key) }
    extra = (normalized.keys - FIELD_ORDER).sort
    (known + extra).map { |key| "#{key}=#{render_value(normalized[key])}" }
  end
  private_class_method :render_fields

  def render_value(value)
    text = normalize_value(value)
    return text if bare_safe?(text)

    escaped = text.gsub("\\") { "\\\\" }.gsub('"') { "\\\"" }
    "\"#{escaped}\""
  end
  private_class_method :render_value

  def bare_safe?(text)
    !text.empty? && !text.match?(/[\s"\\]/)
  end
  private_class_method :bare_safe?

  # --- Parsing ---------------------------------------------------------------

  # timestamp<2sp>subject<2sp>rest, mirroring intent_screen.rb's SAVEPOINT_RE
  # (the same three-field contract every reader in the tree already assumes).
  TRANSITION_LINE_RE = /\A(\S+)#{SEPARATOR}(\S+)#{SEPARATOR}(.+?)\s*\z/.freeze
  private_constant :TRANSITION_LINE_RE

  FIELD_TOKEN_RE = /([a-z_]+)=("(?:[^"\\]|\\.)*"|[^\s"]+)/.freeze
  private_constant :FIELD_TOKEN_RE

  # Parse one raw ledger line into {timestamp:, subject:, state:, fields:,
  # comment:, raw:}, or nil when it does not even split into the three fields
  # every transition line has. `#scrub`s the line first (mirrors
  # SessionLedger.parse_checklist_line) so a stray non-UTF-8 byte anywhere in
  # the ledger never raises out of the parser and takes down every reader
  # (matrix 2.44); it only ever affects that one line's parsed text.
  def parse_transition_line(line)
    raw = line.to_s.chomp.scrub
    m = TRANSITION_LINE_RE.match(raw)
    return nil unless m

    timestamp, subject, rest = m.captures
    state, remainder = rest.split(/\s+/, 2)
    fields, comment = scan_fields(remainder.to_s)
    { timestamp: timestamp, subject: subject, state: state, fields: fields, comment: comment, raw: raw }
  end

  # Scan `rest` (everything after the state token) for `key=value` pairs, quote-
  # and-escape aware, greedily from the start; the first token that is not a
  # pair, and everything after it, is the trailing comment (spec D8), with one
  # layer of wrapping parens stripped when present (the shape #transition_line
  # itself always emits). Returns [fields_hash, comment_or_nil].
  def scan_fields(rest)
    scanner = StringScanner.new(rest)
    fields = {}
    loop do
      scanner.skip(/\s+/)
      break if scanner.eos?

      start_pos = scanner.pos
      if scanner.scan(FIELD_TOKEN_RE)
        fields[scanner[1]] = unquote(scanner[2])
      else
        scanner.pos = start_pos
        break
      end
    end
    tail = scanner.rest.to_s.strip
    comment = tail.empty? ? nil : tail.sub(/\A\((.*)\)\z/m, '\1')
    [fields, comment]
  end
  private_class_method :scan_fields

  def unquote(raw)
    return raw unless raw.start_with?('"')

    raw[1..-2].gsub(/\\(.)/) { Regexp.last_match(1) }
  end
  private_class_method :unquote

  # A transition line is torn (spec D9) when it does not parse into the three
  # fields at all, when its state token is outside STATES, or when its state is
  # in STATES but a field REQUIRED_FIELDS demands is missing. The second half
  # matters more than the first: a crash-truncated write usually keeps a valid
  # state token and loses the tail (`n1  running holder=auto-ce5`), which is
  # the realistic torn line, not a truncated state token.
  def torn?(line)
    parsed = parse_transition_line(line)
    return true unless parsed
    return true unless parsed[:state] && STATES.include?(parsed[:state])

    missing_fields(parsed[:state], parsed[:fields]).any?
  end

  def torn_reason(parsed)
    return "does not parse as timestamp  subject  state ..." unless parsed && parsed[:state]
    return "unknown state #{parsed[:state].inspect}" unless STATES.include?(parsed[:state])

    "missing required field(s): #{missing_fields(parsed[:state], parsed[:fields]).join(', ')}"
  end
  private_class_method :torn_reason

  # A transition line is attributed (spec D10) iff it carries a non-blank
  # `holder=` field. Unattributed and torn are independent: a line can be
  # unattributed and otherwise well formed at the same time.
  def attributed?(parsed)
    return false unless parsed

    present?((parsed[:fields] || {})["holder"])
  end

  def resolved_state(state)
    RESOLUTION.fetch(state.to_s, state.to_s)
  end

  # --- Reading the ledger ------------------------------------------------------

  # Every transition candidate line in `path`, in file order, each annotated
  # with its parse, torn-ness, and attribution. Non-candidate lines (a stage
  # line, a Lock takeover line) are excluded entirely: they are never a
  # transition and are never reported as torn by this module (spec Acceptance
  # Criteria; Savepoint's own phantom detector covers the stage family).
  # `#scrub`s the whole file up front (matrix 2.44) so one bad byte anywhere
  # never raises out of this reader.
  def entries(path)
    return [] unless path && File.exist?(path)

    File.read(path).scrub.each_line.filter_map do |raw|
      line = raw.chomp
      next nil if line.strip.empty?
      next nil unless Savepoint.transition_candidate?(line)

      parsed = parse_transition_line(line)
      torn = torn?(line)
      {
        raw: line,
        timestamp: parsed && parsed[:timestamp],
        subject: parsed ? parsed[:subject] : line.split(/\s{2,}/)[1],
        state: parsed && parsed[:state],
        fields: parsed ? parsed[:fields] : {},
        comment: parsed && parsed[:comment],
        torn: torn,
        attributed: parsed ? attributed?(parsed) : false,
      }
    end
  end

  # Status per subject: the last NON-TORN line for that subject in FILE order
  # (never by timestamp, spec Acceptance Criteria), resolved (spec D2). An
  # unattributed-but-well-formed line still counts for status (D10: status
  # shows it; only the readiness check ignores it).
  def status(path)
    entries(path).each_with_object({}) do |entry, memo|
      next if entry[:torn]

      memo[entry[:subject]] = resolved_state(entry[:state])
    end
  end

  # A subject with no line at all reads as "planned" (spec D1's implicit
  # starting state), never raises.
  def status_for(path, subject)
    status(path).fetch(subject.to_s, "planned")
  end

  # The last (file-order) non-torn `running` entry for `subject`, or nil. Used
  # by the reclaim precondition (S3) to find the `expires=` this subject's live
  # dispatch carries.
  def last_running(path, subject)
    entries(path).select { |e| !e[:torn] && e[:subject] == subject.to_s && e[:state] == "running" }.last
  end

  # Torn and unattributed lines, each paired with a reason (spec C2/C5's
  # reader): [{line:, reason:}, ...]. A clean or absent ledger returns []. A
  # torn line is reported once, as torn; a well-formed unattributed line is
  # reported once, as unattributed - the two categories never conflate.
  def anomalies(path)
    entries(path).filter_map do |entry|
      if entry[:torn]
        { line: entry[:raw], reason: "torn: #{torn_reason(parse_transition_line(entry[:raw]))}" }
      elsif !entry[:attributed]
        { line: entry[:raw], reason: "unattributed (no holder=)" }
      end
    end
  end

  # --- Writing -----------------------------------------------------------------

  # Refuse an unknown state or a missing required field BEFORE touching the
  # file (spec C20), then append through `guard` (default GuardedAppend,
  # strict), skipping dedup entirely (spec D11: transition lines never consult
  # savepoint_recorded_pairs). Returns whatever `guard.call` returns
  # (:written); propagates GuardedAppend::Unavailable rather than swallowing it
  # (a caller must never believe a line landed when it did not).
  def append_transition(path, subject:, state:, fields: {}, comment: nil, now: Time.now, guard: GuardedAppend)
    line = transition_line(subject: subject, state: state, fields: fields, comment: comment, now: now)
    guard.call(path, strict: true) { |_content| line }
  end

  # --- The temporary `needs` reader (spec Approach; replaced by 334) ---------

  # TEMPORARY (comment naming 334, spec Approach "Alternatives Considered"):
  # reads only the intent's own graph.md `## Graph` section, in the D41 shape
  # (327 spec D41 - `## Goal`, `## Decisions`, `## Graph`, `## Status`), for one
  # node's `needs` targets. 334 ships the real graph.md parser (node envelope,
  # kind, files, budget, cycle check) and this method is replaced wholesale;
  # until then this is the only place the G2 readiness precondition (S3) finds
  # a node's needs when `--needs` is not given explicitly.
  #
  # Line shape this reads (one line per node, inside `## Graph` only):
  #   - <node-id> (<kind>) needs: <comma-separated node ids, or "none">
  GRAPH_SECTION_RE = /^##\s+Graph\s*$(.*?)(?=^##\s|\z)/m.freeze
  private_constant :GRAPH_SECTION_RE

  GRAPH_NEEDS_LINE_RE = /\A-\s*(\S+)\s*(?:\([^)]*\))?\s*needs:\s*(.*)\z/i.freeze
  private_constant :GRAPH_NEEDS_LINE_RE

  def needs_from_graph(graph_path, node)
    return [] unless graph_path && File.exist?(graph_path)

    section = File.read(graph_path)[GRAPH_SECTION_RE, 1].to_s
    section.each_line do |line|
      m = GRAPH_NEEDS_LINE_RE.match(line.strip)
      next unless m
      next unless m[1] == node.to_s

      rest = m[2].to_s.strip
      return [] if rest.empty? || rest.casecmp("none").zero?

      return rest.split(",").map(&:strip).reject(&:empty?)
    end
    []
  end
end
