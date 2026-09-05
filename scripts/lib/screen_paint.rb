# encoding: UTF-8
# frozen_string_literal: true

require_relative "intent_screen_ansi"

# ScreenPaint (intent 317a, D1) - the paint seam 317's Needs-you named. Parses
# the plain Markdown screens our own renderers emit (intent, state, roster,
# delivered, delay) and re-lays them out in the shipped intent-screen ANSI
# vocabulary. A parser and RE-LAYOUTER, not a colorizer (A5): the plain
# screens are pipe tables whose scaffolding rows only disappear under a
# Markdown renderer, so the painter drops them and rebuilds the layout;
# content-survival is the contract - every value and note survives, nothing
# is invented, and text it does not recognize returns nil so every caller
# fails open to plain.
#
# Harness-agnostic core: no harness assumption lives here. No ENV, no TTY. Color, width, and
# markdown_safe are caller arguments, exactly like IntentScreenAnsi before it
# (316a1); the 318 ceiling holds - the palette is IntentScreenAnsi's, no new
# colors, no box borders.
#
# Intent 331a (D6): a registry, so a new screen KIND is a new file
# (scripts/lib/screens/<kind>.rb, calling `register` on load), never a diff
# to this one. `paint:` is optional and defaults to the shared pipeline
# below — no shipped kind has its own palette; `classify`/`paint` branch on
# LINE SHAPE, never on kind. The registry's job is only that a new kind's
# opener is recognized without editing this file, and that a kind CAN
# supply its own paint lambda on the rare day one needs one.
module ScreenPaint
  A = IntentScreenAnsi

  # A screen's first line: "## ▶ id · name", "## ✔ id · name · delivered",
  # "▶ In delivery · ...", "✔ id · name · delivered in ...". Retained for
  # reference (and as the union every shipped kind below decomposes into);
  # `classify`/`paint` consult the registry, not this constant, directly.
  OPENER_RE = /\A(?:## )?[▶✔] .+ · /.freeze

  FIELD_LINE_RE = /\A(Stage|Next|Changed|Lead|Progress)(\s{2,})(.*)\z/.freeze
  STEP_LINE_RE = /\A(S\d+)\s+\[ (open|done) \]\s+(.*)\z/.freeze
  TIMELINE_RE = /\A(\d\d:\d\d)\s{2}(\S+)\s{2}(.*)\z/.freeze
  COUNT_LINE_RE = /\A\d+ open( · .*)?\z/.freeze
  BOLD_LEAD_RE = /\A\*\*([^*]+)\*\*(.*)\z/.freeze

  # Intent 317a1 (D3, D4, D5): the data-table palette. Kind and note columns
  # are chosen by the table's own header, never by position; a cell whose
  # text is exactly "not recorded" greys wherever it appears.
  EVIDENCE_PROOF_KINDS = %w[suite red ship doctor deposits verdict].freeze
  EVIDENCE_DEVIATION_KINDS = %w[deviates].freeze
  NOTE_HEADERS = %w[Source Why].freeze
  NOT_RECORDED = "not recorded"

  @registry = {}

  module_function

  # Registers a screen kind's opener grammar (a Regexp or a callable taking
  # the stripped opener line and returning truthy/falsy), plus an optional
  # `paint:` lambda for a kind that needs its own palette (`call(text,
  # color:, width:, markdown_safe:)`). Idempotent by kind: registering the
  # same kind again replaces its entry rather than adding a second one.
  def register(kind, opener:, paint: nil)
    @registry[kind.to_sym] = { opener: opener, paint: paint }
  end

  # Every registered kind's name, shipped and caller-added alike.
  def kinds
    @registry.keys
  end

  # The first registered kind whose opener matches `text` (an already
  # stripped, single line), or nil.
  def opener_kind(text)
    @registry.find { |_, entry| opener_matches?(entry[:opener], text) }&.first
  end

  def opener_matches?(opener, text)
    opener.respond_to?(:call) ? !!opener.call(text) : !!opener.match?(text)
  end

  # The classifier both paint and region_end share. `idx`/`opener_idx` give
  # the positional rule its footing: the line right after a title is the meta
  # line (delivered/delay print one), recognizable by its " · " separators.
  def classify(line, idx: nil, opener_idx: nil)
    text = line.chomp
    stripped = text.strip
    return :blank if stripped.empty?
    return :opener if text == stripped && !opener_kind(stripped).nil?
    return :table if text.lstrip.start_with?("|")
    return :bold if BOLD_LEAD_RE.match?(stripped) && text == stripped
    return :meta if idx && opener_idx && idx == opener_idx + 1 && stripped.include?(" · ")
    return :indented if text.start_with?("  ")
    return :field if FIELD_LINE_RE.match?(text)
    return :step if STEP_LINE_RE.match?(text)
    return :timeline if TIMELINE_RE.match?(text)
    return :count if COUNT_LINE_RE.match?(stripped)
    return :closer if ["None", "not recorded", "No intents in delivery.", "No intents delivered in this session."].include?(stripped)
    :unknown
  end

  # Where the screen region ends inside a larger message (B10): walk from the
  # opener while every line classifies; the first unknown line - ordinary
  # prose, a prose bullet - is the boundary. Never consumes past the screen.
  def region_end(lines, start_idx)
    i = start_idx + 1
    while i < lines.length
      kind = classify(lines[i], idx: i, opener_idx: start_idx)
      break if kind == :unknown
      # A bare "**Section**" head belongs to the screen only when what follows
      # is still grammar; "**What this means**" over prose bullets is the
      # model's own commentary and stays outside, unsplit (B10).
      if kind == :bold && bare_bold?(lines[i]) && !grammar_follows?(lines, i, start_idx)
        break
      end
      i += 1
    end
    # Trailing blanks belong to the message, not the screen.
    i -= 1 while i > start_idx + 1 && lines[i - 1].strip.empty?
    i
  end

  def bare_bold?(line)
    m = BOLD_LEAD_RE.match(line.strip)
    m && m[2].to_s.strip.empty?
  end

  def grammar_follows?(lines, idx, opener_idx)
    j = idx + 1
    j += 1 while j < lines.length && lines[j].strip.empty?
    return false if j >= lines.length
    kind = classify(lines[j], idx: j, opener_idx: opener_idx)
    kind != :unknown && kind != :opener
  end

  # The painter. Returns the ANSI (or plain re-laid, when color: false) text,
  # or nil when the input does not open with a screen title or carries a line
  # outside the grammar - the caller's cue to print the original untouched.
  def paint(text, color: true, width: A::DEFAULT_WIDTH, markdown_safe: false)
    lines = text.to_s.lines
    first_idx = lines.index { |l| !l.strip.empty? }
    return nil if first_idx.nil?

    kind = opener_kind(lines[first_idx].strip)
    # Intent 330 (D7/O3.26): a screen that is nothing but a single known
    # closer line (e.g. "No intents delivered in this session.") has no
    # opener to require - it is already the whole, honest message.
    return nil unless kind || classify(lines[first_idx]) == :closer

    # Intent 331a (D6): a registered kind MAY supply its own paint lambda;
    # when it does, this whole call delegates to it instead of the shared
    # pipeline below. No shipped kind does.
    if kind
      custom = @registry[kind][:paint]
      return custom.call(text, color: color, width: width, markdown_safe: markdown_safe) if custom
    end

    out = +""
    table = []
    ok = true
    indent_run = 0

    flush = lambda do
      next if table.empty?
      out << paint_table(table, color: color, width: width, markdown_safe: markdown_safe)
      table.clear
    end

    lines.each_with_index do |line, idx|
      kind = classify(line, idx: idx, opener_idx: first_idx)
      # Intent 317a1 (O6, D8): the run counter tracks consecutive :indented
      # lines so only the SECOND and later lines under a heading like
      # "**Asked**" grey as a note; a :table line (which `next`s below) must
      # reset it too, so a later unrelated indented block starts fresh.
      indent_run = kind == :indented ? indent_run + 1 : 0
      if kind == :table
        table << line.strip
        next
      end
      flush.call
      case kind
      when :opener
        t = clean(line.strip.sub(/\A## /, ""), markdown_safe)
        out << A.fit(t, width) { |s| A.styled(s, color, A::BOLD, A::NEARWHITE) } << "\n"
      when :meta
        out << A.fit(clean(line.strip, markdown_safe), width) { |s| A.styled(s, color, A::MIDGREY) } << "\n"
      when :bold
        m = BOLD_LEAD_RE.match(line.strip)
        head = A.styled(clean(m[1], markdown_safe), color, A::BOLD, A::NEARWHITE)
        out << head << clean(m[2], markdown_safe) << "\n"
      when :indented
        text = A.fit_plain(clean(line.chomp, markdown_safe), width)
        out << (indent_run > 1 ? A.styled(text, color, A::MIDGREY) : text) << "\n"
      when :field
        m = FIELD_LINE_RE.match(line.chomp)
        out << A.styled(m[1].ljust(8), color, A::BOLD) << "  " << clean(m[3], markdown_safe) << "\n"
      when :step
        m = STEP_LINE_RE.match(line.chomp)
        badge = A.status_cell(m[2] == "done", color)
        out << "#{m[1].ljust(4)} [#{badge}]  #{A.fit_plain(clean(m[3], markdown_safe), width - 12)}\n"
      when :timeline
        # Intent 317a1 (O5, D6, D7): the time carries no escape at all; the
        # kind label carries the color - amber for the review turning point,
        # teal for a landed commit, mid-grey (no bold) otherwise.
        m = TIMELINE_RE.match(line.chomp)
        codes = case m[2]
                when "Review" then [A::BOLD, A::AMBER]
                when "Commit" then [A::BOLD, A::TEAL]
                else [A::MIDGREY]
                end
        out << m[1] << "  " << A.styled(m[2].ljust(6), color, *codes) << "  " << clean(m[3], markdown_safe) << "\n"
      when :count
        out << A.fit(line.strip, width) { |s| A.styled(s, color, A::MIDGREY) } << "\n"
      when :closer
        out << A.styled(line.strip, color, A::MIDGREY) << "\n"
      when :blank
        out << "\n"
      else
        ok = false
        break
      end
    end
    flush.call
    return nil unless ok

    paint_bars(out.gsub(/\n{3,}/, "\n\n"), color)
  end

  # --- tables -----------------------------------------------------------------

  SEPARATOR_RE = /\A\|[\s:|-]+\|?\z/.freeze

  def cells_of(row)
    row.split("|", -1).map(&:strip)[1..-2].to_a
  end

  def field_table?(rows)
    rows.first&.gsub(/[\s|]/, "") == "" || cells_of(rows.first).first.to_s.start_with?("**")
  end

  # A field table ("| | | |" scaffold, "| **Key** | value | note |" rows)
  # re-lays as the intent screen's three-column field block: bold key,
  # value, and a mid-grey note that shares the line when it fits, dropping
  # to its own line only as a fallback (D9-D11). A data table re-lays as
  # padded columns with a bold header, done/open cells colored, no pipes
  # anywhere.
  def paint_table(rows, color:, width:, markdown_safe:)
    rows = rows.reject { |r| SEPARATOR_RE.match?(r) || r.gsub(/[\s|]/, "").empty? }
    return "" if rows.empty?

    if cells_of(rows.first).first.to_s.start_with?("**")
      return paint_field_table(rows, color: color, width: width, markdown_safe: markdown_safe)
    end

    paint_data_table(rows, color: color, markdown_safe: markdown_safe)
  end

  # Intent 317a1 (O3, D9-D11, D14, D15): the same three-column geometry as
  # IntentScreenAnsi.render's field-row loop, on the SAME implementation
  # (D12) - `IntentScreenAnsi.field_table_lines` - so the two renderers
  # cannot drift apart. Notes arrive as plain text here, so `visible_width`
  # equals `length`, but the shared helper is used anyway so both renderers
  # read identically.
  def paint_field_table(rows, color:, width:, markdown_safe:)
    key_w = rows.map { |r| cells_of(r).first.to_s.gsub("*", "").length }.max
    field_rows = rows.map do |row|
      key, value, note = cells_of(row)
      key = key.to_s.gsub("*", "")
      [key, clean(value.to_s, markdown_safe), clean(note.to_s, markdown_safe)]
    end
    A.field_table_lines(field_rows, width: width, color: color, key_width: key_w)
  end

  # Intent 317a1 (O4, D3-D5): a data table's kind and note columns are chosen
  # by the header, never by position; a cell whose text is exactly "not
  # recorded" greys wherever it appears. `widths[ci] || 0` (rather than a
  # bare `widths[ci]`) is the ragged-row guard: `ReportScreen.escape` writes
  # `\|` while `cells_of` still splits on every `|`, so a row can carry more
  # cells than its header without either side ever raising.
  def paint_data_table(rows, color:, markdown_safe:)
    grid = rows.map { |r| cells_of(r).map { |c| clean(c, markdown_safe) } }
    widths = grid.first.each_index.map { |i| grid.map { |r| r[i].to_s.length }.max }
    kind_col = grid.first.first == "Kind" ? 0 : nil
    note_col = grid.first.index { |h| NOTE_HEADERS.include?(h) }

    out = +""
    grid.each_with_index do |cols, ri|
      last_ci = cols.length - 1
      cells = cols.each_with_index.map do |cell, ci|
        padded = ci == last_ci ? cell.to_s : cell.to_s.ljust(widths[ci] || 0)
        # An empty cell never gets styled (317a1 post-exec review, finding
        # 1): `A.styled("", ...)` still emits a color-open/RESET pair around
        # nothing visible, and that hides the join separator's own trailing
        # spaces from `.rstrip` below, on the very line the reader sees.
        next padded if cell.to_s.empty?
        if ri.zero?
          A.styled(padded, color, A::BOLD)
        elsif ci == kind_col && EVIDENCE_PROOF_KINDS.include?(cell)
          A.styled(padded, color, A::TEAL, A::BOLD)
        elsif ci == kind_col && EVIDENCE_DEVIATION_KINDS.include?(cell)
          A.styled(padded, color, A::AMBER, A::BOLD)
        elsif ci == note_col
          A.styled(padded, color, A::MIDGREY)
        elsif cell == "done"
          A.styled(padded, color, A::TEAL)
        elsif cell == "open"
          A.styled(padded, color, A::AMBER)
        elsif cell == NOT_RECORDED
          A.styled(padded, color, A::MIDGREY)
        else
          padded
        end
      end
      out << "  " << cells.join("  ").rstrip << "\n"
    end
    out
  end

  def paint_bars(text, color)
    return text unless color
    text.gsub(/█+/) { |run| "#{A::TEAL}#{run}#{A::RESET}" }
        .gsub(/░+/) { |run| "#{A::MIDGREY}#{run}#{A::RESET}" }
  end

  def clean(text, markdown_safe)
    markdown_safe ? A.clean(text) : text
  end

  # --- the five shipped kinds (intent 331a, D6) -----------------------------
  #
  # Each opener is a strict subset of OPENER_RE, decomposed by shape rather
  # than by any per-kind palette: `intent`/`state` share the exact template
  # line (templates/intent-screen.md and templates/report-state.md both open
  # with "## ▶ {{id}} · {{name}}"); `delivered` narrows to the "## ✔ id ·
  # name · delivered" shape report_screen.rb emits; `roster` and `delay`
  # cover every bare (no "## ") glyph line, which is exactly ScreenPaint's
  # original, single OPENER_RE decomposed into its "## "-prefixed half and
  # its bare half — the union is unchanged, so no existing screen stops
  # being recognized.
  register(:intent, opener: /\A## [▶✔] .+ · /)
  register(:state, opener: /\A## [▶✔] .+ · /)
  register(:delivered, opener: /\A## ✔ .+ · /)
  register(:roster, opener: /\A▶ .+ · /)
  register(:delay, opener: /\A✔ .+ · /)
end
