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
# below - no shipped kind has its own palette; `classify`/`paint` branch on
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
  # 331a1: the session verb prints this note between the delivered screens and
  # the roster (report_screen.rb, render_session). It is our own output, so the
  # painter must not reject it - the live hook trace caught the region stopping
  # dead on it, with the whole roster below reaching the terminal as plain
  # Markdown. Pinned to the exact shape rather than "any sentence": region_end
  # exists to stop at the model's own prose, and a loose rule would swallow it.
  SKIP_NOTE_RE = /\A\d+ completed intents? skipped: .+\z/.freeze
  # 331a2 (D5, S3): render_session's own rescue card when a directory's delivered screen
  # raises (report_screen.rb:1466-1468) - our own output, not model prose. The census (331a2)
  # proved it classified :unknown, orphaning the roster below it in a real reply. `:meta`, not
  # a new kind: it is a one-line grey note under a title and paint's `:meta` arm reads only
  # `line.strip`, with no positional dependency.
  RESCUE_CARD_RE = /\A## \S+ · could not render \(.*\)\z/.freeze
  BOLD_LEAD_RE = /\A\*\*([^*]+)\*\*(.*)\z/.freeze

  # Intent 317a1 (D3, D4, D5): the data-table palette. Kind and note columns
  # are chosen by the table's own header, never by position; a cell whose
  # text is exactly "not recorded" greys wherever it appears.
  EVIDENCE_PROOF_KINDS = %w[suite red ship doctor deposits verdict].freeze
  EVIDENCE_DEVIATION_KINDS = %w[deviates].freeze
  # "Reason" is the current header (D5, intent 331f); "Why" stays too so a screen captured
  # before the rename still paints (the header map's own forgiving-reader guarantee).
  NOTE_HEADERS = %w[Source Why Reason].freeze
  NOT_RECORDED = "not recorded"

  # Intent 331f (finding 1, post-exec review): the width bound a column shrink never crosses,
  # and the glyphs that mark a column as a progress bar, never itself shrunk. Shared with
  # ReportScreen.fit_table_block (report_screen.rb requires this file, not the other way
  # around) so a markdown row and a painted row bound their columns the same way.
  FIT_COLUMN_FLOOR = 8
  PROGRESS_BAR_CHARS_RE = /[█░]/.freeze

  @registry = {}

  module_function

  # Intent 331f1 (spec.md's acceptance rule): the conservative terminal cost used ONLY to
  # enforce the 115-column bound - ANSI escapes stripped, then every character at or above
  # U+1100 (the East Asian Wide/Ambiguous threshold; a block glyph like "█"/"░" sits well past
  # it) counts two columns, everything else one. `IntentScreenAnsi.visible_width` stays a
  # plain ANSI-stripped `.length` because it drives PADDING, not the bound - a terminal that
  # draws "█" one column wide would misalign if padding used this conservative cost.
  # Over-bounding only ever makes a row narrower, never wraps one, so using this rule for the
  # bound alone is always safe.
  WIDE_CODEPOINT_MIN = 0x1100

  def display_columns(text)
    text.to_s.gsub(A::ANSI_RE, "").each_char.sum { |c| c.ord >= WIDE_CODEPOINT_MIN ? 2 : 1 }
  end

  # Truncate `text` to at most `max_chars` DISPLAY COLUMNS, cutting at the last whitespace at
  # or before the limit (never mid-word) and appending a single ellipsis when truncation
  # happens. The one shared implementation (intent 331f, finding 1; intent 331f1 finding A1):
  # ReportScreen.truncate_on_word_boundary and dashboard.rb's own helper of the same name both
  # delegate here. The ellipsis (U+2026) itself sits above WIDE_CODEPOINT_MIN, so it costs TWO
  # display columns even though it is one character - the budget reserves that display width,
  # not `ellipsis.length`, or every truncated cell lands one column over (finding A1). Any
  # ellipsis already trailing the word-boundary slice is dropped before the fresh one is
  # appended, so a value truncated twice (the assembled-row backstop truncating a cell that
  # was already cut) never stacks a second ellipsis onto the first.
  def truncate_on_word_boundary(text, max_chars)
    t = text.to_s
    return t if display_columns(t) <= max_chars
    ellipsis = A::ELLIPSIS
    budget = [max_chars - display_columns(ellipsis), 0].max
    # Walk characters accumulating DISPLAY columns, not a raw character index: the row-level
    # backstop calls this on an ALREADY-ASSEMBLED row that can carry several prior per-cell
    # ellipses (each one two display columns for one character), so a plain `t[0, limit]`
    # character slice can under-cut and still land over budget once its own wide characters
    # are counted.
    cols = 0
    cut_at = 0
    t.each_char do |c|
      w = c.ord >= WIDE_CODEPOINT_MIN ? 2 : 1
      break if cols + w > budget
      cols += w
      cut_at += 1
    end
    slice = t[0, cut_at]
    cut = slice.rindex(/\s/)
    slice = slice[0, cut] if cut && cut.positive?
    slice = slice.rstrip
    slice = slice.chomp(ellipsis) while slice.end_with?(ellipsis)
    "#{slice}#{ellipsis}"
  end

  # Shrinks a row of column `widths` until their sum fits `budget`: the widest shrinkable
  # column loses one column at a time, ties break toward the leftmost column, no column ever
  # drops below its own `floors[i]` (FIT_COLUMN_FLOOR for every column when `floors` is
  # omitted, the original behavior), and a column flagged in `bar_columns` (it carries a
  # progress bar) is never touched regardless of its floor. The one shared shrink (intent
  # 331f, finding 1; intent 331f1, S3): ReportScreen.fit_table_block's markdown row and
  # ScreenPaint.paint_data_table's painted row both bound through this rather than carrying
  # two loops that could drift apart. Returns a new array; the caller's own `widths` is left
  # untouched.
  def shrink_column_widths(widths, budget, bar_columns:, floors: nil)
    floors ||= Array.new(widths.length, FIT_COLUMN_FLOOR)
    widths = widths.dup
    loop do
      break if widths.sum <= budget
      candidates = widths.each_index.select { |ci| !bar_columns[ci] && widths[ci] > floors[ci] }
      break if candidates.empty?
      target = candidates.max_by { |ci| [widths[ci], -ci] }
      widths[target] -= 1
    end
    widths
  end

  # Intent 331f1, S3 (brief 4): the per-column floor a data-table shrink never crosses - a
  # column never shrinks below its own header cell, below its natural width when that is at
  # most 10 columns (the id case: an id column is already narrow, so "natural width" IS its
  # floor and a uniform 8-column floor could still crush it), or below a bar cell (bar columns
  # are handled separately, by `bar_columns:` above, but a caller may still pass a natural
  # width here too - `[header_len, base].max` never fights that).
  def column_floor(header_len, natural_width)
    base = natural_width <= 10 ? natural_width : FIT_COLUMN_FLOOR
    [header_len, base].max
  end

  # Intent 331f1 (post-execution review, findings P2/P3): a padded cell renders as its column
  # width (characters, from `ljust`) plus that cell's own DISPLAY overage -
  # `display_columns(cell) - cell.length` - because a progress-bar glyph or an already-embedded
  # ellipsis costs more display columns than characters. Crediting overage only to columns
  # flagged `bar_columns:` (the old rule) misses a padded cell that carries an ellipsis in an
  # ordinary text column - exactly what ReportScreen.fit_row_cell hands roadmap_state's Intent
  # column - so the assembled row can still land over the bound even though every column width
  # was computed correctly. The real cost is per ROW, not per column: `rows_of_cells` is an
  # array of rows, each an array of already-stripped, not-yet-padded/truncated cell strings, and
  # this returns the worst row's total overage - the one number ScreenPaint.paint_data_table,
  # ReportScreen.fit_table_block, and ReportScreen.fit_field_table_block all reserve out of their
  # budget, so the three renderers spend one rule rather than three copies that can drift.
  def row_display_overage(rows_of_cells)
    rows_of_cells.map { |cells| cells.sum { |c| display_columns(c.to_s) - c.to_s.length } }.max || 0
  end

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
    return :meta if RESCUE_CARD_RE.match?(stripped)
    return :indented if text.start_with?("  ")
    return :field if FIELD_LINE_RE.match?(text)
    return :step if STEP_LINE_RE.match?(text)
    return :timeline if TIMELINE_RE.match?(text)
    return :count if COUNT_LINE_RE.match?(stripped) || SKIP_NOTE_RE.match?(stripped)
    return :closer if ["None", "not recorded", "No intents in delivery.", "No intents delivered in this session."].include?(stripped)
    :unknown
  end

  # Where the screen region ends inside a larger message (B10): walk from the
  # opener while every line classifies; the first unknown line - ordinary
  # prose, a prose bullet - is the boundary. Never consumes past the screen.
  #
  # 331a1: `opener_idx` tracks the NEAREST preceding opener, not the first
  # one in the message. A reply can carry several screens back to back - the
  # roster is a table then ten cards, the session report is many delivered
  # screens - and `classify`'s positional rule is "the line right after a
  # title", which means the title above it. Testing every line against the
  # message's first opener made the timestamp under the SECOND screen
  # :unknown, and the region stopped there: 30 lines of a 350-line session
  # report painted, the rest reaching the terminal as plain Markdown.
  def region_end(lines, start_idx)
    i = start_idx + 1
    opener_idx = start_idx
    while i < lines.length
      kind = classify(lines[i], idx: i, opener_idx: opener_idx)
      break if kind == :unknown
      opener_idx = i if kind == :opener
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

  # The first line the grammar rejects, walking from the opener under the same
  # nearest-opener rule region_end uses. Returns [index, line] or nil when the
  # whole run classifies. 331a1: this is what the opt-in hook trace reports,
  # so a live run says which line stopped the region instead of leaving it to
  # be guessed from a terminal capture.
  def first_rejected(lines, start_idx)
    opener_idx = start_idx
    ((start_idx + 1)...lines.length).each do |i|
      kind = classify(lines[i], idx: i, opener_idx: opener_idx)
      return [i, lines[i].to_s.rstrip] if kind == :unknown

      opener_idx = i if kind == :opener
    end
    nil
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

    # 331a1: the same nearest-opener rule region_end uses - a reply carrying
    # several screens must classify each one's meta line against its own
    # title, not against the first title in the message.
    opener_idx = first_idx

    lines.each_with_index do |line, idx|
      kind = classify(line, idx: idx, opener_idx: opener_idx)
      opener_idx = idx if kind == :opener
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

  # Intent 331f1 (finding A3): the ONE classifier, called by both this painter and
  # ReportScreen.fit_table_block's field-vs-data dispatch, so a table is never fitted by one
  # rule and painted by another. A block is a field table when EVERY non-separator,
  # non-blank-scaffold row's first cell is bold - not just the first row (the old rule):
  # a data table whose header cell happens to be bold (e.g. "**Kind**") still has ordinary,
  # unbold data rows underneath it, so it stays a data table. A block with nothing left after
  # stripping separators/scaffolding classifies as neither (false).
  def field_table?(rows)
    candidates = rows.reject { |r| SEPARATOR_RE.match?(r) || r.gsub(/[\s|]/, "").empty? }
    return false if candidates.empty?
    candidates.all? { |r| cells_of(r).first.to_s.start_with?("**") }
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

    if field_table?(rows)
      return paint_field_table(rows, color: color, width: width, markdown_safe: markdown_safe)
    end

    paint_data_table(rows, color: color, width: width, markdown_safe: markdown_safe)
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
  #
  # Intent 331f (finding 1, post-exec review): padding every cell to its column's max across
  # ALL rows can paint a row wider than `width` even when every plain row on its own measured
  # under the bound (D7 is on the RENDERED row) - a row short in one column but maximal in
  # another paints wider than its own plain row ever was. `width` bounds the column widths the
  # same way ReportScreen.fit_table_block bounds a markdown row's, through the one shared
  # shrink, before any cell is padded or joined.
  def paint_data_table(rows, color:, width:, markdown_safe:)
    grid = rows.map { |r| cells_of(r).map { |c| clean(c, markdown_safe) } }
    ncols = grid.first.length
    widths = (0...ncols).map { |i| grid.map { |r| r[i].to_s.length }.max }
    bar_columns = (0...ncols).map { |i| grid.any? { |r| r[i].to_s =~ PROGRESS_BAR_CHARS_RE } }
    # Intent 331f1 (post-exec review, P2/P3): the shared row-overage rule, not a per-column bar
    # credit - see ScreenPaint.row_display_overage's own comment for why the bar-only credit
    # missed a padded cell carrying an ellipsis.
    overage = row_display_overage(grid)
    # Intent 331f1, S3 (brief 4): per-column minimums - never below the header cell, never
    # below a natural width of 10 or less (the id case).
    header_len = (0...ncols).map { |i| grid.first[i].to_s.length }
    floors = (0...ncols).map { |i| bar_columns[i] ? widths[i] : column_floor(header_len[i], widths[i]) }
    budget = width - (2 + 2 * (ncols - 1)) - overage
    widths = shrink_column_widths(widths, budget, bar_columns: bar_columns, floors: floors)
    kind_col = grid.first.first == "Kind" ? 0 : nil
    note_col = grid.first.index { |h| NOTE_HEADERS.include?(h) }

    out = +""
    grid.each_with_index do |cols, ri|
      last_ci = cols.length - 1
      texts = cols.each_with_index.map do |cell, ci|
        text = cell.to_s
        w = widths[ci]
        text = truncate_on_word_boundary(text, w) if w && text.length > w
        ci == last_ci ? text : text.ljust(w || 0)
      end

      # Intent 331f1 (post-exec review, P4): the row-level backstop. Even with every column
      # pinned at its floor, the assembled PLAIN row can still exceed `width` once padding/bar/
      # ellipsis overage is counted - shrink the widest SHRINKABLE cell's PLAIN TEXT (never a
      # bar column, and always before styling, since truncating an already-styled string cuts
      # ANSI escapes mid-sequence) until the row fits or nothing is left to shrink.
      loop do
        row_dw = display_columns(("  " + texts.join("  ")).rstrip)
        break if row_dw <= width
        excess = row_dw - width
        shrinkable = (0...ncols).reject { |ci| bar_columns[ci] }
        break if shrinkable.empty?
        target = shrinkable.max_by { |ci| display_columns(texts[ci]) }
        cur_dw = display_columns(texts[target])
        # A bare ellipsis alone already costs 2 display columns; below that floor there is
        # nothing left to cut. Also bail the moment a cut makes no progress (a text already at
        # or under the ellipsis floor re-truncates to the same "…" forever) - a row this wide
        # even at every floor is the documented extreme case, not an infinite loop.
        break if cur_dw <= 2
        shrunk = truncate_on_word_boundary(texts[target].rstrip, [cur_dw - excess, 2].max)
        break if display_columns(shrunk) >= cur_dw
        texts[target] = shrunk
      end

      cells = texts.each_with_index.map do |padded, ci|
        cell = cols[ci]
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
  # its bare half - the union is unchanged, so no existing screen stops
  # being recognized.
  register(:intent, opener: /\A## [▶✔] .+ · /)
  register(:state, opener: /\A## [▶✔] .+ · /)
  register(:delivered, opener: /\A## ✔ .+ · /)
  register(:roster, opener: /\A▶ .+ · /)
  register(:delay, opener: /\A✔ .+ · /)
end
