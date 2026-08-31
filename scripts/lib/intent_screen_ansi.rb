# encoding: UTF-8
# frozen_string_literal: true

require_relative "intent_screen"

# IntentScreenAnsi (intent 316a, O2) - renders one intent screen with raw
# truecolor ANSI escapes, productionizing 318's mockup--render.rb. Standard
# library only. Calls the SAME public IntentScreen.* field methods
# scripts/intent-screen calls (store_fields, index_fields, savepoint_fields,
# checklist_items, progress_fields, next_fields, insight_fields,
# items_present?, fallback_name, step_text) and re-derives nothing, so every
# field the ANSI block prints is the identical value the plain screen prints
# (D3), just carried through a different layout.
#
# `color:` is a constructor/call argument, never an environment read (D18):
# the plain path (`color: false`) is one call away and testable without
# touching NO_COLOR or a TTY. No ENV, no Dir.pwd, no Dir.home.
#
# Harness-agnostic core: no harness assumption lives here. `markdown_safe:`
# (intent 316a1, D3/D5) is the one choice a caller supplies rather than a
# choice this module makes for itself: a display surface that passes raw
# ANSI through untouched should not inherit a concession it never needed.
# See docs/reference/harness-adapters.md for which caller asks for it and
# why.
module IntentScreenAnsi
  ESC = "\e"
  RESET = "#{ESC}[0m".freeze
  BOLD = "#{ESC}[1m".freeze
  TEAL = "#{ESC}[38;2;45;212;191m".freeze
  AMBER = "#{ESC}[38;2;245;158;11m".freeze
  GRAPHITE_BG = "#{ESC}[48;2;31;41;55m".freeze
  MIDGREY = "#{ESC}[38;2;148;163;184m".freeze
  NEARWHITE = "#{ESC}[38;2;243;244;246m".freeze

  BAR_CELLS = 24
  EIGHTHS = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"].freeze

  # Intent 317a1 (D14): the approved design is a 115-column layout, measured
  # from design--terminal-output.html:52-58 with its tags stripped.
  DEFAULT_WIDTH = 115

  ELLIPSIS = "…"

  # Intent 317a1 (D9-D11, D15): the three-column field table's geometry.
  # ANSI_RE strips escapes so padding measures what the terminal actually
  # draws (D10); VALUE_COL_MAX is the design's own value-column figure and
  # the owner's "50 chars" (mockup--report-screen.md:74); NOTE_FLOOR is the
  # minimum note length that earns the own-line fallback when the note alone
  # (not the value) is what overflows the same-line budget.
  ANSI_RE = /\e\[[0-9;]*m/.freeze
  VALUE_COL_MAX = 50
  NOTE_FLOOR = 24

  def self.visible_width(text)
    text.to_s.gsub(ANSI_RE, "").length
  end

  def self.render(intent_dir:, store_root:, color: true, width: DEFAULT_WIDTH, markdown_safe: false)
    base = File.basename(intent_dir)
    id = base.split("--", 2).first
    intent_text = File.read(File.join(intent_dir, "#{base}.md"))

    fields = {}
    fields.merge!(IntentScreen.store_fields(store_root))
    status, title = IntentScreen.index_fields(store_root, id)
    fields["status"] = status
    fields["status.note"] = status == "unlisted" ? "no INDEX.md line names this id" : "listed under ## #{status} in INDEX.md"
    fields["id"] = id
    fields["name"] = title || IntentScreen.fallback_name(intent_text)
    fields.merge!(IntentScreen.savepoint_fields(intent_dir, intent_text))
    items = IntentScreen.checklist_items(intent_dir)
    fields.merge!(IntentScreen.progress_fields(items))
    fields.merge!(IntentScreen.next_fields(items, status, checklist_present: IntentScreen.items_present?(intent_dir), escape_pipes: false))
    fields.merge!(IntentScreen.insight_fields(intent_text, escape_pipes: false))
    fields.transform_values! { |v| markdown_safe ? clean(v) : v }

    done_n = fields["progress.done"].to_i
    total_n = fields["progress.total"].to_i

    out = +""
    out << fit("▶ #{fields['id']} · #{fields['name']}", width) { |t| styled(t, color, BOLD, NEARWHITE) }
    out << "\n\n"

    # The 4th column marks a row whose value is already a finished, pre-fit
    # string (the Progress bar, built above from styled glyphs plus a count)
    # rather than raw field text still needing `fit_plain`. Naming that
    # explicitly here reads better than testing the value for a leading ESC
    # byte further down, which is really just asking "is this the Progress
    # row?" through a type check.
    field_rows = [
      ["Store", fields["store"], fields["store.note"], false],
      ["Status", fields["status"], fields["status.note"], false],
      ["Stage", fields["stage"], fields["stage.note"], false],
      ["Savepoint", fields["savepoint"], fields["savepoint.note"], false],
      ["Progress", "#{render_bar(done_n, total_n, color)}  #{done_n} / #{total_n}", fields["progress.note"], true],
      ["Next", fields["next"], fields["next.note"], false],
      ["Insight", fields["insight"], fields["insight.note"], false],
    ]
    key_width = field_rows.map { |k, _, _, _| k.length }.max

    out << field_table_lines(field_rows, width: width, color: color, key_width: key_width)

    out << "\n"
    out << fit("Steps", width) { |t| styled(t, color, BOLD, NEARWHITE) }
    out << "\n\n"

    if items.empty?
      out << "  no steps yet\n"
    else
      # Padded to the widest label (matrix B2): at 10+ steps "S10" is one
      # column wider than "S1..S9", and without padding every badge past S9
      # drifts out of column with the rows above it.
      label_width = "S#{items.size}".length
      items.each_with_index do |item, i|
        num = "S#{i + 1}".ljust(label_width)
        badge = status_cell(item[:done], color)
        prefix_plain = "  #{num}  [ #{item[:done] ? 'done' : 'open'} ]  "
        text_budget = [width - prefix_plain.length, 0].max
        step = IntentScreen.step_text(item[:text])
        text = fit_plain(markdown_safe ? clean(step) : step, text_budget)
        out << "  #{num}  [#{badge}]  #{text}\n"
      end
    end

    out
  end

  # --- shared field-table geometry (D9-D12, D14, D15) ------------------------

  # The field table's basis, cap, budget arithmetic, both fallbacks, and the
  # right-strip, shared by `render` above and `ScreenPaint.paint_table`'s
  # `**Key**` branch, so the two renderers can never drift apart (D12) - the
  # duplication this replaced was character-for-character identical apart
  # from the module prefix. `rows` is `[key, value, note]`, or `[key, value,
  # note, true]` when `value` is already a finished, pre-fit string (the
  # Progress bar) rather than raw text still needing `fit_plain`.
  #
  # Notes become a third column, padded to the widest RENDERED noted value
  # (capped at VALUE_COL_MAX, D15) so every note starts at one raw-text
  # position; a row whose value or note will not fit drops to the
  # note-on-its-own-line form instead of squeezing anything invisibly. When
  # the same-line budget has already collapsed to zero or less, the note
  # falls straight to its own line rather than being fed to `fit` and
  # silently returning "" - the note must be cut with a visible ellipsis or
  # kept whole, never dropped outright (317a1 post-exec review, finding 4).
  def self.field_table_lines(rows, width:, color:, key_width:)
    prefix_width = key_width + 4 # "  " + key.ljust + "  "

    rendered_rows = rows.map do |key, value, note, prebuilt|
      value_budget = [width - prefix_width, 0].max
      value_text = prebuilt ? value : fit_plain(value.to_s, value_budget)
      [key.to_s, value_text, note.to_s]
    end

    noted_widths = rendered_rows.filter_map { |_, value_text, note| visible_width(value_text) unless note.empty? }
    value_col = [noted_widths.max.to_i, VALUE_COL_MAX].min
    note_budget = width - prefix_width - value_col - 2

    out = +""
    rendered_rows.each do |key, value_text, note|
      row = "  #{styled(key.ljust(key_width), color, BOLD)}  #{value_text}"
      if note.empty?
        out << row.rstrip << "\n"
        next
      end

      value_fits = visible_width(value_text) <= value_col
      note_width = visible_width(note)
      note_overflows = note_width > note_budget
      note_fits = !note_overflows || (note_budget.positive? && note_width <= NOTE_FLOOR)
      if value_fits && note_fits
        pad = value_col - visible_width(value_text)
        out << row << (" " * pad) << "  " << fit(note, note_budget) { |t| styled(t, color, MIDGREY) } << "\n"
      else
        out << row.rstrip << "\n"
        own_budget = [width - prefix_width, 0].max
        out << (" " * prefix_width) << fit(note, own_budget) { |t| styled(t, color, MIDGREY) } << "\n"
      end
    end
    out
  end

  # --- markdown-noise stripping, adapter-optional (intent 316a1, D3/D5) ------
  #
  # Not every display surface passes text through a Markdown renderer, so
  # stripping is not this module's call to make (see `markdown_safe:` on
  # `render` above; the justification for WHY a caller would ever ask for
  # this lives with that caller, in scripts/lib/message_display.rb). When
  # asked, strips backticks and neutralises `*`/`_` runs from a value.
  # Single underscores are left alone: they are common inside ordinary words
  # (`intent_screen.rb`) and GFM does not treat an intraword underscore as
  # emphasis; only a run of 2+ (the bold marker `__`) is markdown-active.
  def self.clean(text)
    text.to_s.delete("`*").gsub(/_{2,}/, "")
  end

  # --- width cap (D15, matrix 18) --------------------------------------------

  # Truncates `text` to `max` visible columns with a trailing ellipsis when
  # cut, then yields the truncated plain text to the block for coloring.
  # Coloring never adds visible width. The cap itself is harness-neutral: a
  # fixed width, not a re-flow, is what lets a column layout survive whatever
  # display eventually shows it — no display's own wrapping is assumed here.
  def self.fit(text, max)
    plain = fit_plain(text, max)
    block_given? ? yield(plain) : plain
  end

  def self.fit_plain(text, max)
    return "" if max <= 0
    return text if text.length <= max
    return ELLIPSIS[0, max] if max <= 1

    "#{text[0, max - 1]}#{ELLIPSIS}"
  end

  # --- palette ----------------------------------------------------------------

  def self.styled(text, color, *codes)
    return text unless color

    "#{codes.join}#{text}#{RESET}"
  end

  def self.status_cell(done, color)
    label = done ? " done " : " open "
    return label unless color

    hue = done ? TEAL : AMBER
    "#{hue}#{BOLD}#{label}#{RESET}"
  end

  # `.dup` matters, not just style (318's own note, carried forward): these
  # constants are built via string interpolation, which frozen_string_literal
  # does NOT freeze automatically — only static literals get that. `.freeze`
  # above makes them immutable, but `bar << ...` below still needs its OWN
  # mutable copy or it would raise (or, without the freeze, silently corrupt
  # the shared constant for every later call in the same process — matrix 16).
  def self.render_bar(done, total, color)
    ratio = total.zero? ? 0.0 : done.to_f / total

    unless color
      on = total.zero? ? 0 : (done * BAR_CELLS) / total
      return ("#" * on) + ("." * (BAR_CELLS - on))
    end

    units = (ratio * BAR_CELLS * 8).round.clamp(0, BAR_CELLS * 8)
    full, rem = units.divmod(8)
    full = [full, BAR_CELLS].min

    bar = TEAL.dup
    bar << ("█" * full)
    if full < BAR_CELLS && rem.positive?
      bar << EIGHTHS[rem]
      full += 1
    end
    track = BAR_CELLS - full
    bar << GRAPHITE_BG << (" " * track) if track.positive?
    bar << RESET
    bar
  end
end
