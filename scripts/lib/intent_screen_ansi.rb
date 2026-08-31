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

  DEFAULT_WIDTH = 100

  ELLIPSIS = "…"

  def self.render(intent_dir:, store_root:, color: true, width: DEFAULT_WIDTH)
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
    fields.transform_values! { |v| clean(v) }

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
    prefix_width = key_width + 4 # "  " + key.ljust + "  "

    field_rows.each do |key, value, note, prebuilt|
      value_budget = [width - prefix_width, 0].max
      value_text = prebuilt ? value : fit_plain(value, value_budget)
      out << "  #{styled(key.ljust(key_width), color, BOLD)}  #{value_text}\n"
      next if note.to_s.empty?

      note_budget = [width - prefix_width, 0].max
      indent = " " * prefix_width
      out << "#{indent}#{fit(note, note_budget) { |t| styled(t, color, MIDGREY) }}\n"
    end

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
        text = fit_plain(clean(IntentScreen.step_text(item[:text])), text_budget)
        out << "  #{num}  [#{badge}]  #{text}\n"
      end
    end

    out
  end

  # --- markdown-noise stripping (intent 316a, S1 answer 5 / matrix 19b) ------
  #
  # `displayContent` is still Markdown-processed by Claude Code even inside a
  # raw ANSI block (a live capture showed backticks silently stripped from
  # step text). Strip backticks and neutralise `*`/`_` runs from every value
  # before it reaches the block, so nothing is left for that pass to act on.
  # Single underscores are left alone: they are common inside ordinary words
  # (`intent_screen.rb`) and GFM does not treat an intraword underscore as
  # emphasis; only a run of 2+ (the bold marker `__`) is markdown-active.
  def self.clean(text)
    text.to_s.delete("`*").gsub(/_{2,}/, "")
  end

  # --- width cap (D15, matrix 18) --------------------------------------------

  # Truncates `text` (already markdown-clean) to `max` visible columns with a
  # trailing ellipsis when cut, then yields the truncated plain text to the
  # block for coloring. Coloring never adds visible width.
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
