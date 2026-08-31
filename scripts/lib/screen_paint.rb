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
module ScreenPaint
  A = IntentScreenAnsi

  # A screen's first line: "## ▶ id · name", "## ✔ id · name · delivered",
  # "▶ In delivery · ...", "✔ id · name · delivered in ...".
  OPENER_RE = /\A(?:## )?[▶✔] .+ · /.freeze

  FIELD_LINE_RE = /\A(Stage|Next|Changed|Lead|Progress)(\s{2,})(.*)\z/.freeze
  STEP_LINE_RE = /\A(S\d+)\s+\[ (open|done) \]\s+(.*)\z/.freeze
  TIMELINE_RE = /\A(\d\d:\d\d)\s{2}(\S+)\s{2}(.*)\z/.freeze
  COUNT_LINE_RE = /\A\d+ open( · .*)?\z/.freeze
  BOLD_LEAD_RE = /\A\*\*([^*]+)\*\*(.*)\z/.freeze

  module_function

  # The classifier both paint and region_end share. `idx`/`opener_idx` give
  # the positional rule its footing: the line right after a title is the meta
  # line (delivered/delay print one), recognizable by its " · " separators.
  def classify(line, idx: nil, opener_idx: nil)
    text = line.chomp
    stripped = text.strip
    return :blank if stripped.empty?
    return :opener if OPENER_RE.match?(stripped) && text == stripped
    return :table if text.lstrip.start_with?("|")
    return :bold if BOLD_LEAD_RE.match?(stripped) && text == stripped
    return :meta if idx && opener_idx && idx == opener_idx + 1 && stripped.include?(" · ")
    return :indented if text.start_with?("  ")
    return :field if FIELD_LINE_RE.match?(text)
    return :step if STEP_LINE_RE.match?(text)
    return :timeline if TIMELINE_RE.match?(text)
    return :count if COUNT_LINE_RE.match?(stripped)
    return :closer if ["None", "not recorded", "No intents in delivery."].include?(stripped)
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
    return nil unless classify(lines[first_idx]) == :opener

    out = +""
    table = []
    ok = true

    flush = lambda do
      next if table.empty?
      out << paint_table(table, color: color, width: width, markdown_safe: markdown_safe)
      table.clear
    end

    lines.each_with_index do |line, idx|
      kind = classify(line, idx: idx, opener_idx: first_idx)
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
        out << A.fit_plain(clean(line.chomp, markdown_safe), width) << "\n"
      when :field
        m = FIELD_LINE_RE.match(line.chomp)
        out << A.styled(m[1].ljust(8), color, A::BOLD) << "  " << clean(m[3], markdown_safe) << "\n"
      when :step
        m = STEP_LINE_RE.match(line.chomp)
        badge = A.status_cell(m[2] == "done", color)
        out << "#{m[1].ljust(4)} [#{badge}]  #{A.fit_plain(clean(m[3], markdown_safe), width - 12)}\n"
      when :timeline
        m = TIMELINE_RE.match(line.chomp)
        out << A.styled(m[1], color, A::MIDGREY) << "  " << A.styled(m[2].ljust(6), color, A::BOLD) \
            << "  " << clean(m[3], markdown_safe) << "\n"
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
  # re-lays as the intent screen's vertical field block: bold key, value,
  # mid-grey note on its own line. A data table re-lays as padded columns
  # with a bold header, done/open cells colored, no pipes anywhere.
  def paint_table(rows, color:, width:, markdown_safe:)
    rows = rows.reject { |r| SEPARATOR_RE.match?(r) || r.gsub(/[\s|]/, "").empty? }
    return "" if rows.empty?

    if cells_of(rows.first).first.to_s.start_with?("**")
      out = +""
      key_w = rows.map { |r| cells_of(r).first.to_s.gsub("*", "").length }.max
      rows.each do |row|
        key, value, note = cells_of(row)
        key = key.to_s.gsub("*", "")
        out << "  #{A.styled(key.ljust(key_w), color, A::BOLD)}  #{clean(value.to_s, markdown_safe)}\n"
        next if note.to_s.empty?
        out << (" " * (key_w + 4)) << A.fit(clean(note, markdown_safe), width - key_w - 4) { |s| A.styled(s, color, A::MIDGREY) } << "\n"
      end
      return out
    end

    grid = rows.map { |r| cells_of(r).map { |c| clean(c, markdown_safe) } }
    widths = grid.first.each_index.map { |i| grid.map { |r| r[i].to_s.length }.max }
    out = +""
    grid.each_with_index do |cols, ri|
      cells = cols.each_with_index.map do |cell, ci|
        padded = cell.to_s.ljust(widths[ci])
        if ri.zero?
          A.styled(padded, color, A::BOLD)
        elsif cell == "done"
          A.styled(padded, color, A::TEAL)
        elsif cell == "open"
          A.styled(padded, color, A::AMBER)
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
end
