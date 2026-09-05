# encoding: UTF-8
# frozen_string_literal: true

# ReportScreen (intent 317) - the record readers plus the three renderers
# (state, delivered, delay) behind scripts/report-screen. Every rendered cell
# traces to a file on disk (D14): a missing source renders the exact string
# "not recorded", never a guess or a blank. Pure: explicit paths in, a string
# out. Dependency injection for anything reaching outside the fixture: the
# clock is passed as `now:`, git tag reading as `tag_reader:`, and the ANSI
# renderer path as `renderer_path:` (D2).
require "time"
require "json"
require "date"
require_relative "intent_screen"
require_relative "lock"
require_relative "session_ledger"
require_relative "roadmap_queue"
require_relative "roadmap_savepoint"
require_relative "screen_paint"

module ReportScreen
  NOT_RECORDED = "not recorded"

  # --- shared helpers ----------------------------------------------------------

  def self.intent_basename(intent_dir)
    File.basename(intent_dir)
  end

  def self.intent_id(intent_dir)
    intent_basename(intent_dir).split("--", 2).first
  end

  def self.intent_file_path(intent_dir)
    File.join(intent_dir, "#{intent_basename(intent_dir)}.md")
  end

  def self.intent_text(intent_dir)
    path = intent_file_path(intent_dir)
    File.exist?(path) ? File.read(path) : nil
  end

  def self.spec_text(intent_dir)
    path = File.join(intent_dir, "spec.md")
    File.exist?(path) ? File.read(path) : nil
  end

  def self.outcome_text(intent_dir)
    path = File.join(intent_dir, "outcome.md")
    File.exist?(path) ? File.read(path) : nil
  end

  # The body of a top-level "## Heading" section, stopping at the next "## "
  # heading (same idiom as IntentScreen.insight_fields). Returns "" when the
  # heading is absent.
  def self.section_of(text, heading)
    return "" unless text
    text.split(/^#{Regexp.escape(heading)}\s*$/, 2)[1].to_s.split(/^## /, 2)[0].to_s
  end

  def self.escape(text)
    text.to_s.gsub("|", "\\|")
  end

  # --- width bound (D7, intent 331f) --------------------------------------------
  #
  # ReportScreen.fit_screen(text, limit:) is the one shared pass every public render entry
  # point in this file (and dashboard.rb's screen renderer) calls last, so no rendered row
  # ever passes the limit. Input unchanged byte for byte when nothing is over the limit.

  FIT_SCREEN_DEFAULT_LIMIT = 115
  # The column floor and the progress-bar glyph regex are ScreenPaint's own (intent 331f,
  # finding 1): ScreenPaint.paint_data_table shrinks a painted row's columns through the same
  # rule this file's own fit_table_block uses, so both aliases point at the one definition
  # rather than carrying a second copy that could drift.
  FIT_SCREEN_COLUMN_FLOOR = ScreenPaint::FIT_COLUMN_FLOOR
  PROGRESS_BAR_CHARS_RE = ScreenPaint::PROGRESS_BAR_CHARS_RE

  # Truncate `text` to at most `max_chars`, cutting at the last whitespace at or before the
  # limit (never mid-word) and appending a single ellipsis when truncation happens. The one
  # shared implementation now lives on ScreenPaint (intent 331f, finding 1); dashboard.rb's own
  # helper of the same name delegates here, and this delegates onward so neither caller's own
  # name has to change.
  def self.truncate_on_word_boundary(text, max_chars)
    ScreenPaint.truncate_on_word_boundary(text, max_chars)
  end

  # Split on every pipe, escaped or not - the SAME rule ScreenPaint.cells_of uses (R3), so the
  # fitter and the painter can never count a row's columns differently. Raw (unstripped) cells,
  # so callers can still tell a padded column from an unpadded one.
  def self.raw_cells_of(row)
    row.split("|", -1)[1..-2].to_a
  end

  # Where a title ends (D8, orchestrator ruling 2026-09-05). A title ends at the first colon
  # FOLLOWED BY A SPACE, which is how a person writes a label before its explanation. Any
  # colon would also cut inside a URL or a clock time and leave a name no reader recognizes:
  # zlatkocodes intent 4 opens "About page redesign and header navigation order. Rebuild
  # https://zlatkocodes.com/about/ ... styling: ..." and used to render as "... Rebuild https".
  # A title can carry both boundaries, and then the earlier one is the name: zlatkocodes 4 also
  # has a real label colon, 130 characters in, long after its opening sentence ends. With
  # neither boundary the title is the whole line.
  # A line that opens with its colon has no label to take, so it falls back the same way. The
  # one implementation: dashboard.rb reads titles through this rather than splitting again.
  TITLE_LABEL_RE = /\A(.*?): /m.freeze
  TITLE_SENTENCE_RE = /\A(.*?[.!?])(?:\s|\z)/m.freeze

  def self.title_before_colon(text, max: 120)
    line = text.to_s.strip
    candidates = [TITLE_LABEL_RE, TITLE_SENTENCE_RE].filter_map { |re| line[re, 1]&.strip }
                                                    .reject(&:empty?)
    truncate_on_word_boundary(candidates.min_by(&:length) || line, max)
  end

  # Intent 331f1 (RC1): every bound check below measures in DISPLAY COLUMNS
  # (ScreenPaint.display_columns - ANSI stripped, a character at or above U+1100 counts two),
  # not String#length - a bar row can pass a character-count check while still over the real
  # 115-column bound, which is exactly why the suite stayed green while real screens rendered
  # over it (spec.md's defect 3/4).
  def self.fit_screen(text, limit: FIT_SCREEN_DEFAULT_LIMIT)
    lines = text.to_s.lines
    return text if lines.all? { |l| ScreenPaint.display_columns(l.chomp) <= limit }

    out = +""
    i = 0
    while i < lines.length
      if lines[i].lstrip.start_with?("|")
        block = []
        while i < lines.length && lines[i].lstrip.start_with?("|")
          block << lines[i]
          i += 1
        end
        out << fit_table_block(block, limit)
      else
        out << fit_plain_line(lines[i], limit)
        i += 1
      end
    end
    out
  end

  def self.fit_plain_line(line, limit)
    body = line.chomp
    return line if ScreenPaint.display_columns(body) <= limit
    ending = line[body.length..].to_s
    "#{truncate_on_word_boundary(body, limit)}#{ending}"
  end

  # Intent 331f1 (finding A3/A5): field tables and data tables get their own fitters
  # (ScreenPaint.field_table? is the ONE classifier both this and the painter use), and the
  # block-level guard above already lets an already-fitting block - every row already at or
  # under `limit` in display columns, exactly what ReportScreen.fit_row_cell/
  # roadmap_state_entries_table already produce for the roadmap Batches table - through
  # untouched, so a table-wide shrink never re-truncates a row a caller already sized
  # correctly (A5).
  def self.fit_table_block(block, limit)
    return block.join if block.all? { |l| ScreenPaint.display_columns(l.chomp) <= limit }

    rows = block.map(&:chomp)
    return fit_field_table_block(block, limit) if ScreenPaint.field_table?(rows)

    is_sep = rows.map { |r| r.match?(ScreenPaint::SEPARATOR_RE) }
    raw_rows = rows.map { |r| raw_cells_of(r) }
    ncols = raw_rows.map(&:length).max.to_i
    return block.join if ncols.zero?

    stripped_cols = Array.new(ncols) { [] }
    stripped_rows = []
    header_idx = raw_rows.each_index.find { |ri| !is_sep[ri] }
    raw_rows.each_with_index do |cells, ri|
      next if is_sep[ri]
      row = (0...ncols).map { |ci| cells[ci].to_s.strip }
      row.each_with_index { |c, ci| stripped_cols[ci] << c }
      stripped_rows << row
    end
    widths = stripped_cols.map { |col| col.map(&:length).max.to_i }

    bar_column = Array.new(ncols) { |ci| stripped_cols[ci].any? { |c| c =~ PROGRESS_BAR_CHARS_RE } }
    # Intent 331f1 (post-exec review, P3): the shared row-overage rule (ScreenPaint.
    # row_display_overage), not a per-column bar credit - the same fix as paint_data_table's
    # own P2, so the two renderers cannot drift apart on what "fits" means.
    overage = ScreenPaint.row_display_overage(stripped_rows)
    # Intent 331f1, S3 (brief 4): per-column minimums - never below the header cell, never
    # below a natural width of 10 or less (the id case).
    header_len = Array.new(ncols) { |ci| header_idx ? raw_rows[header_idx][ci].to_s.strip.length : 0 }
    floors = (0...ncols).map { |ci| bar_column[ci] ? widths[ci] : ScreenPaint.column_floor(header_len[ci], widths[ci]) }

    # A column is "padded" when at least one non-last, non-separator raw cell carries more
    # than the one mandatory space before its closing pipe - the ljust convention several
    # tables in this file already use (state_rows, roster). Only such a column is re-padded
    # after a shrink; an unpadded table stays unpadded.
    padded_column = Array.new(ncols) do |ci|
      next false if ci == ncols - 1
      raw_rows.each_with_index.any? { |cells, ri| !is_sep[ri] && cells[ci].to_s.end_with?("  ") }
    end

    budget = limit - (4 + 3 * (ncols - 1)) - overage
    widths = ScreenPaint.shrink_column_widths(widths, budget, bar_columns: bar_column, floors: floors)

    fitted_rows = raw_rows.each_with_index.map do |cells, ri|
      if is_sep[ri]
        "| #{widths.map { |w| "-" * [w, 3].max }.join(" | ")} |"
      else
        rendered = cells.each_with_index.map do |c, ci|
          next c.to_s.strip if ci >= ncols
          value = c.to_s.strip
          value = truncate_on_word_boundary(value, widths[ci]) if value.length > widths[ci]
          padded_column[ci] && ci != ncols - 1 ? value.ljust(widths[ci]) : value
        end
        "| #{rendered.join(' | ')} |"
      end
    end

    # F28: the unconditional backstop. Every shrinkable column may already sit at its floor
    # and the assembled row can still be over the limit; truncate the whole row on a word
    # boundary rather than let it survive past 115 - a data table's separator row included
    # (test_fit_screen_backstops_an_unshrinkable_row), unlike the field-table fitter's own
    # separator, which always passes through untouched (W2).
    fitted_rows.map! { |r| ScreenPaint.display_columns(r) > limit ? truncate_on_word_boundary(r, limit) : r }

    "#{fitted_rows.join("\n")}\n"
  end

  # Intent 331f1 (S2, design): the field table's own fitter - a "| | | |" scaffold or
  # "| --- | --- | --- |" separator row passes through byte for byte; the label column
  # (first cell) takes its natural width and never shrinks or truncates; the VALUE column
  # shrinks first, down to a floor of max(24, the widest bar cell in that column) so a
  # progress bar is never cut; only then does the NOTE column shrink, and when what is left
  # for it falls under ScreenPaint::FIT_COLUMN_FLOOR (8) columns the note is dropped whole
  # (never squeezed to "in…") and the value reclaims the freed room, back up to its own
  # natural width. A value that still cannot fit ends with an ellipsis; the value floor is
  # never crossed even then, so the row may still exceed `limit` in that extreme case -
  # there is no row-level backstop here (that backstop is the data-table branch's own, and
  # it must never touch a field table's label cell).
  #
  # Intent 331f1 (post-exec review, P1): `label_w`/`value_w`/`note_w` and `budget` are character
  # counts spent against the 115 DISPLAY-column bound - a bar row's glyphs (2 columns each) or
  # an embedded ellipsis cost more display columns than characters, so a row can pass this
  # arithmetic while still landing well over the real bound. `ScreenPaint.row_display_overage`
  # reserves the worst row's own overage up front (P1-P3's shared fix); a fresh ellipsis this
  # function's OWN truncation adds where none existed before can still leave a small residual,
  # which the corrective loop below closes by re-measuring the actual assembled row and shrinking
  # note (then value, never below its floor) by the exact excess.
  #
  # Intent 331f1 (P5): the label (and, when flagged, the value) column is re-padded exactly the
  # way `fit_table_block`'s own `padded_column` rule would - ljust in CHARACTERS, never display
  # columns, so a terminal drawing a bar glyph one column wide stays aligned - restoring the
  # alignment a fitted field table lost.
  def self.fit_field_table_block(block, limit)
    return block.join if block.all? { |l| ScreenPaint.display_columns(l.chomp) <= limit }

    rows = block.map(&:chomp)
    is_sep = rows.map { |r| r.match?(ScreenPaint::SEPARATOR_RE) }
    content_idx = rows.each_index.reject { |ri| is_sep[ri] }
    return block.join if content_idx.empty?

    raw_content = content_idx.map { |ri| raw_cells_of(rows[ri]) }
    parsed = content_idx.map { |ri| ScreenPaint.cells_of(rows[ri]) }
    ncols = parsed.map(&:length).max.to_i
    return block.join if ncols.zero?

    label_w = parsed.map { |c| c[0].to_s.length }.max.to_i
    value_texts = parsed.map { |c| c[1].to_s }
    natural_value_w = value_texts.map(&:length).max.to_i
    bar_value_w = value_texts.select { |v| v =~ PROGRESS_BAR_CHARS_RE }.map(&:length).max.to_i
    value_floor = [24, bar_value_w].max
    value_w = natural_value_w

    has_note = ncols > 2 && parsed.any? { |c| !c[2].to_s.empty? }
    note_texts = has_note ? parsed.map { |c| c[2].to_s } : []
    note_w = note_texts.map(&:length).max.to_i

    gaps = ncols - 1
    overage = ScreenPaint.row_display_overage(parsed.map { |c| (0...ncols).map { |ci| c[ci].to_s } })
    budget = limit - (4 + 3 * gaps) - overage
    overflow = (label_w + value_w + note_w) - budget

    if overflow.positive?
      shrink = [[overflow, value_w - value_floor].min, 0].max
      value_w -= shrink
      overflow -= shrink
    end

    if overflow.positive? && has_note
      remaining_for_note = note_w - overflow
      if remaining_for_note < FIT_SCREEN_COLUMN_FLOOR
        freed = note_w
        overflow -= freed
        note_w = 0
        has_note = false
        value_w = [value_w - overflow, natural_value_w].min if overflow.negative?
      else
        note_w = remaining_for_note
      end
    end

    # P5: a column (never the last) is "padded" when at least one non-separator RAW cell already
    # ends with two spaces before its closing pipe - the same `padded_column` convention
    # `fit_table_block` uses (state_rows, roster).
    padded_label = raw_content.any? { |cells| cells[0].to_s.end_with?("  ") }
    padded_value = ncols > 2 && raw_content.any? { |cells| cells[1].to_s.end_with?("  ") }

    render = lambda do
      rows.each_index.map do |ri|
        next rows[ri] if is_sep[ri]
        cells = ScreenPaint.cells_of(rows[ri])
        label = cells[0].to_s
        value = cells[1].to_s
        note = has_note ? cells[2].to_s : ""

        value = truncate_on_word_boundary(value, value_w) if value.length > value_w && value !~ PROGRESS_BAR_CHARS_RE
        note = truncate_on_word_boundary(note, note_w) if has_note && note.length > note_w

        label = label.ljust(label_w) if padded_label
        value = value.ljust(value_w) if padded_value

        if has_note
          "| #{label} | #{value} | #{note} |"
        elsif ncols > 2
          "| #{label} | #{value} | |"
        else
          "| #{label} | #{value} |"
        end
      end
    end

    # The corrective pass (P1): measure what actually got assembled, and if it still runs over
    # `limit`, shrink note (then value, down to its floor) by the exact excess and re-render.
    # Bounded: each pass either shrinks a column or breaks, and there are at most two columns
    # left to shrink once the label is fixed.
    loop do
      candidate = render.call
      max_dw = content_idx.map { |ri| ScreenPaint.display_columns(candidate[ri]) }.max.to_i
      break if max_dw <= limit

      excess = max_dw - limit
      progressed = false
      if has_note && note_w.positive?
        cut = [excess, note_w].min
        note_w -= cut
        excess -= cut
        progressed = true if cut.positive?
        if note_w < FIT_SCREEN_COLUMN_FLOOR
          has_note = false
          note_w = 0
        end
      end
      if excess.positive? && value_w > value_floor
        cut = [excess, value_w - value_floor].min
        value_w -= cut
        progressed = true if cut.positive?
      end
      break unless progressed
    end

    "#{render.call.join("\n")}\n"
  end

  # Intent 331f1 (design's final bullet): the shared budget dashboard.rb's screen_fit_intent
  # and roadmap_state_entries_table's Intent cell both spend by - a title cell fitted to
  # whatever the row's OTHER already-rendered cells leave it, measured in display columns
  # (RC1: an `others` cell carrying a progress bar costs two columns per glyph, not one).
  # `others` are the sibling cells as they will actually render; the scaffolding is the
  # leading "| ", a " | " between every pair of cells, and the trailing " |".
  def self.fit_row_cell(title, others, max: FIT_SCREEN_DEFAULT_LIMIT)
    scaffolding = 2 + (3 * others.length) + 2
    budget = max - scaffolding - others.sum { |c| ScreenPaint.display_columns(c.to_s) }
    return "" if budget <= 0
    truncate_on_word_boundary(title, budget)
  end

  def self.frontmatter(intent_dir)
    text = intent_text(intent_dir)
    return {} unless text && text.start_with?("---")
    parts = text.split("---", 3)
    return {} if parts.length < 3
    require "yaml"
    require "date"
    YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}
  rescue StandardError
    {}
  end

  def self.research_intent?(intent_dir)
    Array(frontmatter(intent_dir)["tags"]).map(&:to_s).include?("research")
  end

  # Intent 330 (D12): the shared fence walker feeding split_by_headings AND
  # table_rows. A line matching \A\s{0,3}(```+|~~~+) while closed opens a
  # fence and remembers the marker character and its length; while open, a
  # line whose marker is the SAME character and at least as long, with only
  # whitespace after it, closes the fence. Inside a fence every line is body
  # - a leading "#" or a leading "|" included. A four-space-indented block is
  # deliberately never a fence (the cap is 0-3 leading whitespace chars),
  # which is the CommonMark indented-code case, out of scope on purpose
  # (D12's stated limit). Yields [line, fenced] for every line, in order.
  FENCE_LINE_RE = /\A\s{0,3}(`{3,}|~{3,})/.freeze

  def self.each_fence_line(text)
    return enum_for(:each_fence_line, text) unless block_given?

    marker = nil # [character, length] of the currently open fence, or nil
    text.to_s.each_line do |line|
      if marker
        yield line, true
        m = line.match(FENCE_LINE_RE)
        next unless m && m[1][0] == marker[0] && m[1].length >= marker[1]
        next unless line.sub(FENCE_LINE_RE, "").strip.empty?

        marker = nil
      else
        m = line.match(FENCE_LINE_RE)
        if m
          marker = [m[1][0], m[1].length]
          yield line, true
        else
          yield line, false
        end
      end
    end
  end

  # Markdown pipe-table data rows (header + separator skipped), each an array
  # of trimmed cell strings. Tolerates leading prose before the table. Fence-
  # aware (D12/O1.7): a pipe row inside a fenced example is never counted.
  def self.table_rows(text)
    lines = []
    each_fence_line(text) do |line, fenced|
      next if fenced

      stripped = line.strip
      lines << stripped if stripped.start_with?("|")
    end
    sep_idx = lines.index { |l| l.match?(/\A\|[\s:|-]+\|?\z/) }
    return [] unless sep_idx
    lines[(sep_idx + 1)..].map { |l| l.split("|", -1).map(&:strip)[1..-2].to_a }
  end

  # Every [heading_line, body] pair in a Markdown file, split on ANY heading
  # line (any level). Used by proven_by (D19) so a section's own matrix rows
  # are never confused with a sibling section's. Fence-aware (D12): a "#"
  # line inside a fenced example never starts a new section.
  def self.split_by_headings(text)
    sections = []
    heading = nil
    body = +""
    each_fence_line(text) do |line, fenced|
      if !fenced && line.start_with?("#")
        sections << [heading, body] if heading
        heading = line.strip
        body = +""
      else
        body << line
      end
    end
    sections << [heading, body] if heading
    sections
  end

  def self.savepoint_lines(intent_dir)
    path = File.join(intent_dir, "savepoint.md")
    return [] unless File.exist?(path)
    File.readlines(path).map(&:strip).reject(&:empty?).filter_map do |line|
      m = line.match(IntentScreen::SAVEPOINT_RE)
      m ? [m[1], m[2], m[3]] : nil
    end
  end

  def self.human_time(ts)
    IntentScreen.human_time(ts)
  end

  def self.title_for(intent_dir, store_root)
    text = intent_text(intent_dir)
    return "not recorded" unless text
    if store_root
      _status, title = IntentScreen.index_fields(store_root, intent_id(intent_dir))
      return title if title
    end
    IntentScreen.fallback_name(text)
  end

  def self.default_store_root(intent_dir)
    File.expand_path("../..", intent_dir)
  end

  # --- S3: record readers -------------------------------------------------------

  # Row 21: the ## Intent section body only, never the frontmatter `intent:` line.
  def self.asked(intent_dir)
    text = intent_text(intent_dir)
    return NOT_RECORDED unless text
    body = section_of(text, "## Intent").strip
    body.empty? ? NOT_RECORDED : body
  end

  PLACEHOLDER_SENTINEL = "<!-- plastic:placeholder -->"

  # 317a S3 (A6): the note under Asked. Bulleted decisions in a real spec keep
  # the historic "N decisions in spec.md"; a prose ## Decisions falls back to
  # the highest D<n> it names; a placeholder spec falls through to the intent
  # record's "### Decisions" (which section_of's "^## " anchor cannot reach);
  # nothing anywhere says "decisions not recorded" - never a false 0, and the
  # scaffold's "- ..." never counts as 1.
  def self.decision_note(intent_dir)
    spec = spec_text(intent_dir)
    if spec && !spec.lstrip.start_with?(PLACEHOLDER_SENTINEL)
      n = decisions_in(section_of(spec, "## Decisions"))
      return "#{n} decisions in spec.md" if n.positive?
    end
    n = decisions_in(intent_text(intent_dir).to_s.split(/^### Decisions\s*$/, 2)[1].to_s.split(/^#+ /, 2)[0])
    return "#{n} decisions in the intent record" if n.positive?
    "decisions not recorded"
  end

  def self.decisions_in(body)
    bullets = body.to_s.lines.count { |l| s = l.lstrip; s.start_with?("- ") && s.strip != "- ..." }
    return bullets if bullets.positive?
    body.to_s.scan(/\bD(\d{1,3})\b/).flatten.map(&:to_i).max.to_i
  end

  # Row 22: bullets under spec.md's ## Decisions only.
  def self.decision_count(intent_dir)
    text = spec_text(intent_dir)
    return NOT_RECORDED unless text
    section_of(text, "## Decisions").lines.count { |l| l.lstrip.start_with?("- ") }
  end

  # Rows 23/24: outcome.md's ## Delivered, table or bullet form.
  def self.delivered_rows(intent_dir)
    text = outcome_text(intent_dir)
    return [] unless text
    section = section_of(text, "## Delivered")
    return [] if section.strip.empty?

    rows = table_rows(section)
    return rows.map { |cells| { label: cells[0].to_s, text: cells[1].to_s } } if rows.any?

    bullet_rows(section).each_with_index.map do |text, i|
      { label: (i + 1).to_s, text: text }
    end
  end

  # 317a S1 (matrix S1a/S1b): a bullet row is its "- " line PLUS its wrapped
  # continuation lines - outcome prose is hand-wrapped at ~100 columns, and
  # taking one physical line truncated every real record mid-sentence. A blank
  # line or a heading ends the row; prose after a blank is never swept in.
  def self.bullet_rows(section)
    rows = []
    section.to_s.each_line do |line|
      stripped = line.strip
      if line.lstrip.start_with?("- ")
        rows << line.lstrip.sub(/\A-\s*/, "").strip
      elsif stripped.empty? || line.start_with?("#")
        rows << nil unless rows.empty? || rows.last.nil?
      elsif !rows.empty? && !rows.last.nil?
        rows[rows.length - 1] = "#{rows.last} #{stripped}"
      end
    end
    rows.compact
  end

  # Intent 331b (plan.md, "The one non-additive edit"): the standalone-token
  # rule, extracted so `action_file_for` (the plan screen's Action column)
  # calls the exact same rule as `matching_action_heading` and the two can
  # never drift on what counts as a match. `matching_action_heading`'s own
  # signature, return shape and behavior are unchanged (row P16).
  def self.heading_tokens(heading)
    heading.to_s.sub(/\A#+\s*/, "").split(/[^A-Za-z0-9]+/)
  end

  # Rows 25-27: D19 - the label must appear as a standalone token in an action
  # file heading (any level); the count is the matched section's table rows only.
  def self.matching_action_heading(intent_dir, label)
    Dir.glob(File.join(intent_dir, "actions", "*.md")).sort.each do |path|
      split_by_headings(File.read(path)).each do |heading, body|
        return [heading, body] if heading_tokens(heading).include?(label)
      end
    end
    [nil, nil]
  end

  def self.proven_by(intent_dir, label)
    _heading, body = matching_action_heading(intent_dir, label)
    return NOT_RECORDED unless body
    n = table_rows(body).length
    n.positive? ? "#{n} test#{n == 1 ? '' : 's'}" : NOT_RECORDED
  end

  # Row 34: outcome.md's ## Needs you, our own N1..NN numbering (never the
  # table's own N column, which could be malformed).
  def self.needs_you_rows(intent_dir)
    text = outcome_text(intent_dir)
    return [] unless text
    return [] unless text.include?("## Needs you")
    section = section_of(text, "## Needs you")
    rows = table_rows(section)
    if rows.any?
      return rows.each_with_index.map do |cells, i|
        { n: "N#{i + 1}", what: cells[1].to_s, why: cells[2].to_s }
      end
    end

    # 317a S2 (matrix S2a): prose that exists must never render as None - the
    # 317 record hid three owner picks behind exactly that. One joined row,
    # why "not recorded"; a literal None (or an empty section) stays [].
    content = section.gsub(/<!--.*?-->/m, "").strip
    return [] if content.empty? || content == "None"

    what = content.lines.map(&:strip).reject(&:empty?)
                  .join(" ").sub(/\A-\s*/, "").squeeze(" ")
    [{ n: "N1", what: what, why: NOT_RECORDED }]
  end

  # Row 35: first-to-last savepoint timestamp, "1 h 51 min" / "n min".
  def self.duration(intent_dir)
    lines = savepoint_lines(intent_dir)
    return NOT_RECORDED if lines.length < 2
    secs = (Time.parse(lines.last[0]) - Time.parse(lines.first[0])).to_i
    format_duration(secs)
  end

  def self.format_duration(secs)
    mins = [secs, 0].max / 60
    return "#{mins} min" if mins < 60
    "#{mins / 60} h #{mins % 60} min"
  end

  # Row 36 (D20): mode from the LIVE delivery lock's run_mode; absent -> not recorded.
  def self.mode(intent_dir)
    data = Lock.read(intent_dir)
    value = data && data["run_mode"]
    return value.to_s if value && !value.to_s.empty?

    # 317a S7 (D5): after the close the lock is gone; end-intent stamps the
    # run_mode into outcome.md frontmatter, so mode stops being unknowable
    # retrospectively. Live lock first - it is the source of truth mid-flight.
    value = outcome_frontmatter(intent_dir)["mode"]
    value && !value.to_s.empty? ? value.to_s : NOT_RECORDED
  end

  def self.outcome_frontmatter(intent_dir)
    text = outcome_text(intent_dir)
    return {} unless text && text.start_with?("---")
    parts = text.split("---", 3)
    return {} if parts.length < 3
    require "yaml"
    require "date"
    YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}
  rescue StandardError
    {}
  end

  # --- evidence rows (rows 28-33, 37) --------------------------------------------

  def self.suite_row(section)
    m = section.match(/([\d,]+)\s*runs,\s*([\d,]+)\s*assertions,\s*([\d,]+)\s*failures/)
    return nil unless m
    { kind: "suite", what: "#{m[1]} runs · #{m[2]} assertions · #{m[3]} failures", source: "outcome.md ## Verification" }
  end

  def self.red_row(section)
    line = section.lines.find { |l| l =~ /\bred\b/i && l =~ /`([0-9a-f]{7,40})`/ }
    return nil unless line
    sha = line.match(/`([0-9a-f]{7,40})`/)[1]
    { kind: "red", what: "#{sha} proven test-only and red", source: "outcome.md ## Verification" }
  end

  # Fix 2026-09-01: the record is the truth of delivery (D14: never a guess).
  # The shipped version comes from outcome.md's own ship line first ("Shipped
  # as `v2.0.0-alpha.10`", "released as **v2.0.0-alpha.5**", "released
  # v2.0.0-alpha.9", "Tagged v1.14.1", "Delivered in", "Release v"); the injected tag reader (git) is the
  # fallback when the record is silent. A bare version with no ship verb
  # ("from 1.14.1") is not a shipped version.
  SHIP_VERSION_RE = /\b(?:shipped|released?|delivered|tagged)\b(?:\s+(?:as|in))?[\s`*]*v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?)/i.freeze

  def self.shipped_version(intent_dir)
    text = outcome_text(intent_dir)
    return nil unless text
    m = text.match(SHIP_VERSION_RE)
    m && m[1]
  end

  # The merge commit named on outcome.md's merge line, or nil. The CLI's tag
  # reader asks git which tag contains it; the ship row prints it.
  def self.merge_sha(intent_dir)
    text = outcome_text(intent_dir)
    return nil unless text
    line = text.lines.find { |l| l =~ /\bmerge(d)?\b/i && l =~ /\b[0-9a-f]{7,40}\b/ }
    line && line.match(/\b([0-9a-f]{7,40})\b/)[1]
  end

  # Intent 330 (D9): reads `flow: base:` from a project's project.yml when
  # `intent_dir` sits in the installed project layout
  # (<home>/projects/<slug>/store/<id--slug>); nil otherwise (a global-store
  # intent, a project with no `flow:` key, or malformed YAML). Pure: no git,
  # no shell-out, just the one file this intent's own layout already reads.
  PROJECT_LAYOUT_RE = %r{\A(.*)/projects/([^/]+)/store/[^/]+\z}.freeze

  def self.flow_base(intent_dir)
    m = intent_dir.to_s.match(PROJECT_LAYOUT_RE)
    return nil unless m

    home, slug = m[1], m[2]
    path = File.join(home, "projects", slug, "project.yml")
    return nil unless File.exist?(path)

    require "yaml"
    data = YAML.safe_load(File.read(path))
    return nil unless data.is_a?(Hash)

    flow = data["flow"]
    return nil unless flow.is_a?(Hash)

    base = flow["base"]
    base.is_a?(String) && !base.empty? ? base : nil
  rescue StandardError
    nil
  end

  # Intent 330 (D9/D10/D23): the ship row's WHAT cell is the merge sha, then
  # " → <branch>" only when `branch_reader` answers one (never the "alpha"
  # literal), then " · v<version>" or the existing not-recorded fallback. The
  # Source cell names WHERE the branch came from (D23): project.yml when
  # flow_base itself supplied that exact branch, else git refs, so the row
  # never keeps the stale "git tags" literal for a branch git never answered.
  def self.ship_row(_text, intent_dir, tag_reader, branch_reader: ->(_dir) { nil })
    sha = merge_sha(intent_dir)
    version = shipped_version(intent_dir) || tag_reader.call(intent_dir)
    return nil if sha.nil? && (version.nil? || version.to_s.empty?)
    branch = branch_reader.call(intent_dir)
    sha_text = sha || NOT_RECORDED
    what = +sha_text
    what << " → #{branch}" if branch && !branch.to_s.empty?
    # D10: the version segment is omitted, not filled with NOT_RECORDED. A
    # repository with no release line has no version, the header already
    # carries the shipped identity, and naming the absence twice on one screen
    # is the defect this intent was opened to remove, not a floor worth keeping.
    what << " · v#{version.to_s.sub(/\Av/, '')}" if version && !version.to_s.empty?
    # D14: the cell names every file the row actually came from. The branch and
    # the version have different origins, so when both contributed, both are
    # named rather than only the branch's.
    sources = ["outcome.md"]
    if branch && !branch.to_s.empty?
      sources << (flow_base(intent_dir) == branch ? "project.yml" : "git refs")
    end
    sources << "git tags" if version && !version.to_s.empty? && shipped_version(intent_dir).nil?
    sources << "git tags" if sources.length == 1
    source = sources.join("; ")
    { kind: "ship", what: what, source: source }
  end

  def self.doctor_row(text)
    m = text.to_s.match(/(\d+)\s*pass,?\s*(\d+)\s*warn,?\s*(\d+)\s*fail/i)
    return nil unless m
    { kind: "doctor", what: "#{m[1]} pass · #{m[2]} warn · #{m[3]} fail", source: "outcome.md" }
  end

  def self.deviates_row(section)
    line = section.lines.find { |l| l.lstrip.sub(/\A-\s*/, "").start_with?("Deviation:") }
    return nil unless line
    text = line.lstrip.sub(/\A-\s*/, "").strip
    { kind: "deviates", what: text, source: "outcome.md ## Verification — Deviation:" }
  end

  def self.deposits_row(text)
    line = text.to_s.lines.find { |l| l =~ %r{`resources/[^`]+`} }
    return nil unless line
    path = line.match(%r{`(resources/[^`]+)`})[1]
    { kind: "deposits", what: path, source: "outcome.md" }
  end

  def self.verdict_row(text)
    m = text.to_s.match(/verdict[:\s]+([A-Za-z][A-Za-z ]*)/i)
    return nil unless m
    { kind: "verdict", what: m[1].strip, source: "outcome.md" }
  end

  def self.evidence_rows(intent_dir, tag_reader: ->(_dir) { nil }, branch_reader: ->(_dir) { nil })
    text = outcome_text(intent_dir)
    return [] unless text
    verification = section_of(text, "## Verification")

    rows = []
    rows << suite_row(verification)
    rows << red_row(verification)
    rows << (research_intent?(intent_dir) ? nil : ship_row(text, intent_dir, tag_reader, branch_reader: branch_reader))
    if research_intent?(intent_dir)
      rows << deposits_row(text)
      rows << verdict_row(text)
    end
    rows << doctor_row(text)
    rows << deviates_row(verification)
    rows.compact
  end

  # --- S4/S5: the state verb and the --all roster --------------------------------

  CHANGED_NOTE = "the reason this screen printed"

  def self.state_fields(intent_dir:, store_root:, changed:)
    base = intent_basename(intent_dir)
    id = base.split("--", 2).first
    text = intent_text(intent_dir)
    status, title = IntentScreen.index_fields(store_root, id)
    name = title || IntentScreen.fallback_name(text.to_s)

    f = {}
    f.merge!(IntentScreen.store_fields(store_root))
    f["status"] = status
    f["status.note"] = status == "unlisted" ? "no INDEX.md line names this id" : "listed under ## #{status} in INDEX.md"
    f.merge!(IntentScreen.savepoint_fields(intent_dir, text.to_s))
    items = IntentScreen.checklist_items(intent_dir)
    f.merge!(IntentScreen.progress_fields(items))
    f.merge!(IntentScreen.next_fields(items, status, checklist_present: IntentScreen.items_present?(intent_dir)))
    f.merge!(IntentScreen.insight_fields(text.to_s))

    changed_value = changed && !changed.to_s.empty? ? changed.to_s : "on request"

    rows = [
      ["Store", f["store"], f["store.note"]],
      ["Status", f["status"], f["status.note"]],
      ["Stage", f["stage"], f["stage.note"]],
      ["Savepoint", f["savepoint"], f["savepoint.note"]],
      ["Progress", "#{f['progress.bar']} #{f['progress.done']} / #{f['progress.total']}", f["progress.note"]],
      ["Next", f["next"], f["next.note"]],
      ["Insight", f["insight"], f["insight.note"]],
      ["Changed", changed_value, CHANGED_NOTE],
    ]
    { id: id, name: name, rows: rows, items: items }
  end

  # Rows 42-46: pad BOTH columns to the widest NOTED label/value, computed on
  # the raw emitted (already-escaped) cell text; unnoted rows carry no padding.
  def self.state_rows(rows)
    escaped = rows.map { |label, value, note| ["**#{label}**", escape(value), escape(note)] }
    noted = escaped.select { |_, _, note| !note.to_s.empty? }
    label_w = noted.map { |l, _, _| l.length }.max || 0
    value_w = noted.map { |_, v, _| v.length }.max || 0
    escaped.map do |label, value, note|
      if note.to_s.empty?
        "| #{label} | #{value} | |"
      else
        "| #{label.ljust(label_w)} | #{value.ljust(value_w)} | #{note} |"
      end
    end
  end

  def self.render_state(intent_dir:, store_root:, changed:, template:)
    data = state_fields(intent_dir: intent_dir, store_root: store_root, changed: changed)
    out = template.dup
    out = out.gsub("{{id}}", data[:id])
    out = out.gsub("{{name}}", data[:name])
    out = out.gsub("{{fields.rows}}", state_rows(data[:rows]).join("\n"))
    out = out.gsub("{{steps.rows}}", IntentScreen.steps_rows(data[:items]))
    fit_screen(out.gsub(/\n{3,}/, "\n\n"))
  end

  # --- roster (D7/D8) -------------------------------------------------------------

  # The dirnames named under one "## <section_name>" heading of an INDEX.md.
  # active_dirnames used to hardcode "Active"; intent 330's session verb (D22)
  # reuses this to find Completed/Abandoned dirnames for the no-bookend
  # footer, so the section is now a parameter.
  def self.dirnames_in_section(index_path, section_name)
    return [] unless File.exist?(index_path)
    dirnames = []
    section = nil
    File.foreach(index_path) do |line|
      if line.start_with?("## ")
        section = line[3..].strip
        next
      end
      next unless section == section_name
      m = line.match(%r{\(store/([^/]+)/})
      dirnames << m[1] if m
    end
    dirnames
  end

  def self.active_dirnames(index_path)
    dirnames_in_section(index_path, "Active")
  end

  # Intent 330 (D22): both terminal sections count as "completed" for the
  # no-bookend footer - a closed intent the reader cannot expect a Done
  # savepoint line from, since the convention predates end-intent writing it.
  def self.completed_dirnames(index_path)
    dirnames_in_section(index_path, "Completed") + dirnames_in_section(index_path, "Abandoned")
  end

  def self.newest_savepoint_ts(intent_dir)
    lines = savepoint_lines(intent_dir)
    lines.last&.first
  end

  def self.roster(store_root)
    index_path = File.join(store_root, "INDEX.md")
    entries = active_dirnames(index_path).filter_map do |dirname|
      dir = File.join(store_root, "store", dirname)
      next unless File.directory?(dir)
      text = intent_text(dir).to_s
      fields = IntentScreen.savepoint_fields(dir, text)
      next if fields["stage"] == "Done"
      { dir: dir, id: dirname.split("--", 2).first, ts: newest_savepoint_ts(dir) }
    end
    entries.sort_by { |e| [-(e[:ts] ? Time.parse(e[:ts]).to_i : 0), e[:id]] }
  end

  # D6/R5, intent 331f: one freshness rule for every Lead cell, on the SAME primitive
  # (Lock.who) every call site now shares - a fresh lock prints "agent · key" (this file's
  # own long-standing format), an older lock prints "stale · N min", never idle; no lock, or
  # one that will not read, prints "idle". Lock.who is called ONCE: it already returns the
  # heartbeat timestamp alongside the state, so nothing stats the lock file a second time.
  def self.lead_cell(intent_dir, now: Time.now)
    data = Lock.who(intent_dir, now: now)
    case data["state"]
    when "fresh"
      owner = data["owner"] || {}
      agent = owner["agent"].to_s
      agent = "unknown" if agent.empty? || agent == "unknown"
      session = data["owner_session"].to_s
      "#{agent} · #{session[0, 8]}"
    when "stale"
      mins = [((now - Time.parse(data["heartbeat_at"])) / 60).to_i, 0].max
      "stale · #{mins} min"
    else
      "idle"
    end
  rescue StandardError
    "idle"
  end

  # The roster's own call site (unchanged name/signature at the call sites below); `now:`
  # defaults so a caller that never passed a clock keeps working exactly as before.
  def self.lead(intent_dir, now: Time.now)
    lead_cell(intent_dir, now: now)
  end

  def self.collapsed_open_steps_note(count)
    count <= 3 ? "#{count} open" : "#{count} open · showing the first three"
  end

  def self.render_collapsed_block(intent_dir, store_root, changed:)
    data = state_fields(intent_dir: intent_dir, store_root: store_root, changed: changed)
    stage = data[:rows].find { |l, _, _| l == "Stage" }[1]
    nxt = data[:rows].find { |l, _, _| l == "Next" }[1]
    ch = data[:rows].find { |l, _, _| l == "Changed" }[1]

    open_items = data[:items].each_with_index.reject { |item, _| item[:done] }
    lines = []
    lines << "▶ #{data[:id]} · #{data[:name]}"
    lines << "Stage      #{stage}"
    lines << "Next       #{nxt}"
    lines << "Changed    #{ch}"
    lines << collapsed_open_steps_note(open_items.length)
    open_items.first(3).each { |item, i| lines << "S#{i + 1}   [ open ]  #{escape(item[:text])}" }
    lines.join("\n")
  end

  def self.render_roster(store_root, changed: nil, now: Time.now)
    entries = roster(store_root)
    return "No intents in delivery.\n" if entries.empty?

    header = "▶ In delivery · #{entries.length} #{entries.length == 1 ? 'intent' : 'intents'} · " \
             "#{now.utc.strftime('%Y-%m-%d %H:%M UTC')}"
    table = ["| Graph ID | Stage | Progress | Changed | Lead |", "| --- | --- | --- | --- | --- |"]
    entries.each do |e|
      text = intent_text(e[:dir]).to_s
      savepoint = IntentScreen.savepoint_fields(e[:dir], text)
      items = IntentScreen.checklist_items(e[:dir])
      progress = IntentScreen.progress_fields(items)
      ch = state_fields(intent_dir: e[:dir], store_root: store_root, changed: changed)[:rows].find { |l, _, _| l == "Changed" }[1]
      table << "| #{e[:id]} | #{savepoint['stage']} | #{progress['progress.bar']} #{progress['progress.done']} / #{progress['progress.total']} | #{escape(ch)} | #{lead(e[:dir], now: now)} |"
    end
    blocks = entries.map { |e| render_collapsed_block(e[:dir], store_root, changed: changed) }
    head_and_table = ([header, ""] + table).join("\n")
    # Each collapsed block already has its own internal "\n"; a blank line
    # separates block from block (design--delivery-reports.html:137-152),
    # so they read as distinct entries instead of running together.
    fit_screen("#{head_and_table}\n\n#{blocks.join("\n\n")}\n")
  end

  # --- S6: the delivered verb ------------------------------------------------------

  def self.delivered_timestamp(intent_dir)
    lines = savepoint_lines(intent_dir)
    done = lines.reverse.find { |_ts, kind, _text| kind == "Done" }
    done ? human_time(done[0]) : NOT_RECORDED
  end

  # Intent 330 (D11): the header's last segment is the shipped identity, and
  # says which kind it is - v<version> when a version is known, else
  # "merge <sha>" (never a bare, ambiguous hash), else the exact NOT_RECORDED
  # string when neither exists.
  def self.header_ship_segment(intent_dir, tag_reader)
    version = shipped_version(intent_dir) || tag_reader.call(intent_dir)
    return "v#{version.to_s.sub(/\Av/, '')}" if version && !version.to_s.empty?

    sha = merge_sha(intent_dir)
    return "merge #{sha}" if sha && !sha.to_s.empty?

    NOT_RECORDED
  end

  def self.render_delivered(intent_dir:, tag_reader: ->(_dir) { nil }, branch_reader: ->(_dir) { nil })
    id = intent_id(intent_dir)
    name = title_for(intent_dir, default_store_root(intent_dir))
    ts = delivered_timestamp(intent_dir)
    m = mode(intent_dir)
    dur = duration(intent_dir)
    ship_segment = header_ship_segment(intent_dir, tag_reader)

    lines = []
    lines << "## ✔ #{id} · #{name} · delivered"
    lines << "#{ts} · #{m} · #{dur} · #{ship_segment}"
    lines << ""
    lines << "**Asked**"
    lines << "  #{asked(intent_dir)}"
    lines << "  #{decision_note(intent_dir)}"
    lines << ""
    lines << "**Delivered**"
    lines << "| Row | Detail | Proven by |"
    lines << "| --- | --- | --- |"
    delivered_rows(intent_dir).each do |r|
      lines << "| #{r[:label]} | #{escape(r[:text])} | #{escape(proven_by(intent_dir, r[:label]))} |"
    end
    lines << ""
    lines << "**Evidence**"
    ev = evidence_rows(intent_dir, tag_reader: tag_reader, branch_reader: branch_reader)
    if ev.empty?
      # 317a S4 (matrix S4a): a header-only table (319's live rendering) says
      # nothing; the honest floor is the same phrase every other absent source
      # prints.
      lines << NOT_RECORDED
    else
      lines << "| Kind | Detail | Source |"
      lines << "| --- | --- | --- |"
      ev.each do |r|
        lines << "| #{r[:kind]} | #{escape(r[:what])} | #{escape(r[:source])} |"
      end
    end
    lines << ""
    needsyou = needs_you_rows(intent_dir)
    lines << "**Needs you**"
    if needsyou.empty?
      lines << "None"
    else
      lines << "| N | Need | Reason |"
      lines << "| --- | --- | --- |"
      needsyou.each { |r| lines << "| #{r[:n]} | #{escape(r[:what])} | #{escape(r[:why])} |" }
    end
    fit_screen("#{lines.join("\n")}\n")
  end

  # --- S7: the delay verb -----------------------------------------------------------

  def self.delay_timeline(intent_dir)
    savepoint_lines(intent_dir).map { |ts, kind, text| { ts: ts, kind: kind, text: text } }
  end

  def self.longest_gap(timeline)
    return nil if timeline.length < 2
    best = nil
    timeline.each_cons(2) do |a, b|
      secs = (Time.parse(b[:ts]) - Time.parse(a[:ts])).to_i
      best = { secs: secs, a: a[:kind], b: b[:kind] } if best.nil? || secs > best[:secs]
    end
    "longest gap #{best[:secs] / 60} min, #{best[:a]} to #{best[:b]}"
  end

  def self.where_time_went(timeline)
    gap = longest_gap(timeline)

    unless timeline.any? { |r| %w[Review Commit].include?(r[:kind]) }
      parts = ["the review and commit ledger was not kept for this intent"]
      parts << gap if gap
      return parts.join(" · ")
    end

    rounds = timeline.count { |r| r[:kind] == "Review" }
    commits = timeline.count { |r| r[:kind] == "Commit" }
    parts = []
    parts << "reviews #{rounds} round#{rounds == 1 ? '' : 's'}" if rounds.positive?
    parts << "#{commits} commit#{commits == 1 ? '' : 's'}" if commits.positive?
    parts << gap if gap
    parts.join(" · ")
  end

  def self.hhmm(ts)
    m = ts.match(/T(\d\d:\d\d)/)
    m ? m[1] : ts
  end

  def self.delay_outcome_line(intent_dir)
    text = outcome_text(intent_dir)
    return NOT_RECORDED unless text
    section = section_of(text, "## Summary")
    # The first PARAGRAPH, not just its first physical line - outcome.md's
    # prose is hand-wrapped at ~100 columns, so a single logical sentence
    # spans several source lines.
    paragraph = section.lstrip.split(/\n\s*\n/, 2).first.to_s.lines.map(&:strip).join(" ").strip
    return NOT_RECORDED if paragraph.empty?
    doc = doctor_row(text)
    doc ? "#{paragraph} · #{doc[:what]}" : paragraph
  end

  def self.render_delay(intent_dir:)
    id = intent_id(intent_dir)
    name = title_for(intent_dir, default_store_root(intent_dir))
    dur = duration(intent_dir)
    timeline = delay_timeline(intent_dir)

    lines = []
    lines << "✔ #{id} · #{name} · delivered in #{dur}"
    lines << ""
    timeline.each { |r| lines << "#{hhmm(r[:ts])}  #{r[:kind]}  #{escape(r[:text])}" }
    lines << ""
    lines << "**Where the time went**   #{where_time_went(timeline)}"
    lines << ""
    lines << "**Outcome**   #{delay_outcome_line(intent_dir)}"
    fit_screen("#{lines.join("\n")}\n")
  end

  # --- the plan verb (intent 331b): the PRE-delivery report -----------------------
  #
  # `report-screen plan <intent_dir>` prints the plan the record already
  # carries, before Exec starts: Asked, the decisions count, the planned
  # steps with their action file, and risks. Every cell traces to a file
  # (D3/D14); a missing source prints "not recorded", the same floor every
  # other screen in the family uses, except Mode (D2): a missing lock prints
  # "not armed", never "not recorded" - there is nothing to fall back to
  # before Exec starts.

  VERDICT_TOKENS = %w[PROCEED APPROVE PASS REVISE REWORK FAIL BLOCK].freeze

  # spec.md F4: a checklist line's OWN declared label ("S6 Docs and...")
  # survives here; STEP_PREFIX_RE (IntentScreen's own stripping regex) is
  # reused for the strip, so the label this recognizes is exactly the prefix
  # IntentScreen.checklist_items strips - the two readers can never disagree
  # on where a label ends and the step text begins.
  # The separator class mirrors STEP_PREFIX_RE's own (hyphen, colon, middle
  # dot, em dash, en dash); the latter two are written as \u escapes rather
  # than the literal glyph so this line never trips the project's added-line
  # dash guard, which scans literal characters only - the compiled regex
  # matches identically either way.
  STEP_LABEL_RE = /\A(?:Step\s*|S)\s*(\d+)\s*(?:[-:·\u2014\u2013]\s*|\s+)(?=\S)/i.freeze

  def self.asked_first_sentence(intent_dir)
    body = asked(intent_dir)
    return NOT_RECORDED if body == NOT_RECORDED
    collapsed = body.gsub(/\s+/, " ").strip
    head, rest = IntentScreen.clause_and_rest(collapsed)
    rest ? "#{head}…" : head
  end

  # D5, intent 331f: the plan screen's own Asked row - the intent title before its first
  # colon (F21), never the whole `## Intent` body asked_first_sentence above reads. Most real
  # intent lines read "Short title: the elaborated ask...", so this is the short title; a body
  # with no colon at all (a short intent with no title/elaboration split) renders unchanged,
  # word-boundary truncated the same way every other title cell in the family is.
  def self.plan_asked_title(intent_dir)
    body = asked(intent_dir)
    return NOT_RECORDED if body == NOT_RECORDED
    title_before_colon(body.gsub(/\s+/, " ").strip)
  end

  # spec.md F4: keeps checklist.md's own file order and each line's DECLARED
  # label, falling back to the positional S<n> only when a line declares
  # none - IntentScreen.checklist_items strips the label and renumbers
  # positionally, which is right for the state screen and wrong for the
  # Action lookup below.
  def self.plan_steps(intent_dir)
    return [] unless IntentScreen.items_present?(intent_dir)

    raw = File.readlines(File.join(intent_dir, "checklist.md")).filter_map do |line|
      m = line.match(IntentScreen::ITEM_RE)
      next unless m
      text = m[2].strip
      next if text == "..."
      text
    end

    raw.each_with_index.map do |text, i|
      m = text.match(STEP_LABEL_RE)
      label = m ? "S#{m[1]}" : "S#{i + 1}"
      { label: label, text: text.sub(IntentScreen::STEP_PREFIX_RE, "") }
    end
  end

  # spec.md F3/F6a: the Action column names the file whose heading carries
  # the step's label AND whose section has a matrix table of its own - a
  # heading that resolves but proves nothing is the same hollow-close defect
  # `proven_by` already guards against, so it renders "not recorded" too.
  def self.action_file_for(intent_dir, label)
    Dir.glob(File.join(intent_dir, "actions", "*.md")).sort.each do |path|
      split_by_headings(File.read(path)).each do |heading, body|
        next unless heading_tokens(heading).include?(label)
        return File.basename(path, ".md") if table_rows(body).any?
      end
    end
    NOT_RECORDED
  end

  # D2: mode from the LIVE delivery lock only - unlike `mode` (row 36), a
  # missing lock never falls back to outcome.md's frontmatter (there is
  # nothing to fall back to before Exec starts) and never says the
  # delivered screen's "not recorded"; it says "not armed".
  def self.plan_mode(intent_dir)
    data = Lock.read(intent_dir)
    value = data && data["run_mode"]
    value && !value.to_s.empty? ? value.to_s : "not armed"
  end

  # The last `Review` savepoint line whose text names a PLAN review - a
  # post-execution review line never matches, since its text never contains
  # "plan review".
  def self.plan_review_line(intent_dir)
    savepoint_lines(intent_dir).reverse.find { |_ts, kind, text| kind == "Review" && text =~ /plan review/i }
  end

  def self.plan_reviewer(intent_dir)
    line = plan_review_line(intent_dir)
    return "not reviewed" unless line
    _ts, _kind, text = line
    VERDICT_TOKENS.find { |t| text =~ /\b#{t}\b/ } || NOT_RECORDED
  end

  def self.plan_reviewer_note(intent_dir)
    line = plan_review_line(intent_dir)
    return "-" unless line
    ts, _kind, text = line
    "#{human_time(ts)} · #{text}"
  end

  def self.plan_fields(intent_dir)
    [
      ["Asked", plan_asked_title(intent_dir), "## Intent"],
      ["Decisions", decision_note(intent_dir), "-"],
      ["Steps", "#{plan_steps(intent_dir).length} planned", "checklist.md"],
      ["Mode", plan_mode(intent_dir), "the delivery lock"],
      ["Reviewer", plan_reviewer(intent_dir), plan_reviewer_note(intent_dir)],
    ]
  end

  # plan.md's own ## Risks bullets, wrapped continuations joined (317a's
  # bullet_rows); [] when plan.md is absent or carries no such section - the
  # renderer prints the literal "None" rather than an empty table, the
  # lesson 317a S4 already learned on the Evidence table.
  def self.risk_rows(intent_dir)
    path = File.join(intent_dir, "plan.md")
    return [] unless File.exist?(path)
    bullet_rows(section_of(File.read(path), "## Risks"))
  end

  def self.render_plan(intent_dir:, store_root:, template:)
    id = intent_id(intent_dir)
    name = title_for(intent_dir, store_root)
    steps = plan_steps(intent_dir)

    steps_rows =
      if steps.empty?
        "| | | no steps yet |"
      else
        steps.map do |s|
          "| #{escape(s[:label])} | #{escape(action_file_for(intent_dir, s[:label]))} | #{escape(s[:text])} |"
        end.join("\n")
      end

    risks = risk_rows(intent_dir)
    risks_block =
      if risks.empty?
        "None"
      else
        rows = risks.each_with_index.map { |r, i| "| #{i + 1} | #{escape(r)} |" }
        (["| N | Risk |", "| --- | --- |"] + rows).join("\n")
      end

    out = template.dup
    out = out.gsub("{{id}}", id)
    out = out.gsub("{{name}}", name)
    out = out.gsub("{{fields.rows}}", state_rows(plan_fields(intent_dir)).join("\n"))
    out = out.gsub("{{steps.rows}}", steps_rows)
    out = out.gsub("{{risks.block}}", risks_block)
    fit_screen(out.gsub(/\n{3,}/, "\n\n"))
  end

  # --- S9: the session verb (intent 330) -------------------------------------------
  #
  # `report-screen session <tier_root>` - the delivered screens for every intent
  # this session completed, oldest first, then the state --all roster (D1).
  # Membership is the savepoint Done bookend inside [window_start, now] (D2),
  # never the delivery lock (a dispatched lead's derived auto- key is not the
  # owner's session id). The pure functions below take the clock and the
  # ledger root as arguments (D8): no Time.now, no git, no ENV read here.

  # <home> for a tier root, by the same layout discriminator IntentScreen
  # uses elsewhere: a project tier root's parent directory is "projects".
  def self.home_for_tier_root(tier_root)
    File.basename(File.dirname(tier_root)) == "projects" ? File.expand_path("../..", tier_root) : tier_root
  end

  # D18: <home>/store/.sessions, derived from the tier root through the SAME
  # discriminator - deriving it unconditionally from tier_root would answer
  # "/Users" for the global tier (~/.plastic itself has no "store" segment
  # to strip).
  def self.default_ledger_root(tier_root)
    File.join(home_for_tier_root(tier_root), "store", ".sessions")
  end

  # D5: "global" is <home> itself; any other slug is <home>/projects/<slug>.
  def self.store_for_slug(home, slug)
    slug == "global" ? home : File.join(home, "projects", slug)
  end

  # D4: the newest valid day directory that is not in the future, when
  # `today`'s own day directory does not exist. No ledger at all (D3.13)
  # answers `today` unchanged rather than raising - there is simply nothing
  # to scan, not an error.
  def self.fallback_day(ledger_root, today)
    return today if Dir.exist?(File.join(ledger_root, today))
    return today unless Dir.exist?(ledger_root)

    candidates = Dir.children(ledger_root).select { |d| SessionLedger.valid_day_id?(d) && d <= today }
    candidates.max || today
  end

  # D17: the visible note printed above the screens when no session id was
  # given at all, so the whole-day, tier-only fallback never looks like a
  # real, narrower answer.
  # D17: shaped as a screen opener ("▶ ... · ...") on purpose. The note is the
  # first line of the reply, and both ScreenPaint's OPENER_RE and the
  # MessageDisplay hook's first-character gate require that shape; a plain
  # sentence here would leave the whole session report unpainted.
  def self.window_note(day, reason)
    "▶ Window · the whole of #{Date.strptime(day, '%Y%m%d').iso8601} · #{reason}"
  end

  # True when the day ledger actually carries a line for this session, across
  # the same two day directories the window search reads. The CLI asks so it
  # can tell "no session id given" apart from "this session id matches no
  # ledger line": D17 exists to stop the second one answering silently, and a
  # resumed background job carries exactly that kind of unmatched id.
  def self.session_tagged?(ledger_root:, session:, now:)
    return false if session.nil? || session.to_s.strip.empty?

    short = SessionLedger.short_session_id(session)
    today = SessionLedger.day_id(now)
    yesterday = SessionLedger.day_id(now - 86_400)
    [yesterday, today].any? do |d|
      session_ledger_lines(ledger_root, d).any? { |l| l[:session] == short }
    end
  end

  # D4: local midnight of `day`, converted to UTC, using `sample_now`'s OWN
  # utc_offset - never a literal UTC midnight, and never the machine's
  # ambient zone outside what the injected clock itself carries.
  def self.local_midnight_utc(day, sample_now)
    date = Date.strptime(day, "%Y%m%d")
    Time.new(date.year, date.month, date.day, 0, 0, 0, sample_now.utc_offset)
  end

  # One day's session-tagged savepoint lines: "{ts}  {Event}  [{session}]
  # [{slug}] {summary}" (SessionLedger.savepoint_line's own shape). Missing
  # file, or a line that does not match, is silently skipped.
  SESSION_LEDGER_LINE_RE = /\A(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s{2,}\S+\s{2,}\[([^\]]*)\]\s\[([^\]]*)\]/.freeze

  def self.session_ledger_lines(ledger_root, day)
    path = File.join(ledger_root, day, "savepoint.md")
    return [] unless File.exist?(path)

    File.readlines(path).filter_map do |line|
      m = line.match(SESSION_LEDGER_LINE_RE)
      m ? { ts: m[1], session: m[2], slug: m[3] } : nil
    end
  end

  def self.store_intent_dirs(store)
    Dir.glob(File.join(store, "store", "*")).select { |d| IntentScreen.intent_dir?(d) }
  end

  def self.last_done_ts(intent_dir)
    lines = savepoint_lines(intent_dir)
    done = lines.reverse.find { |_ts, kind, _text| kind == "Done" }
    done ? Time.parse(done[0]) : nil
  end

  # D2/D3/D4/D5/D22: the intent directories completed inside the session's
  # window, oldest Done bookend first, plus the count of completed intents
  # (D22: Completed or Abandoned in INDEX.md) that carry no Done bookend at
  # all and so cannot be placed in any window.
  def self.session_delivered_dirs(ledger_root:, tier_root:, session:, since:, now:)
    today = SessionLedger.day_id(now)
    yesterday = SessionLedger.day_id(now - 86_400)
    short = session && !session.to_s.strip.empty? ? SessionLedger.short_session_id(session) : nil

    tagged = short ? [yesterday, today].flat_map { |d| session_ledger_lines(ledger_root, d) }
                         .select { |l| l[:session] == short } : []
    slugs = tagged.map { |l| l[:slug] }.uniq

    window_start =
      if since
        Time.parse(since.to_s)
      elsif tagged.any?
        tagged.map { |l| Time.parse(l[:ts]) }.min
      else
        local_midnight_utc(fallback_day(ledger_root, today), now)
      end

    home = home_for_tier_root(tier_root)
    stores = ([tier_root] + slugs.map { |s| store_for_slug(home, s) }).uniq
    stores = stores.select { |s| File.exist?(File.join(s, "INDEX.md")) }

    entries = []
    skipped = 0
    stores.each do |store|
      completed = completed_dirnames(File.join(store, "INDEX.md"))
      store_intent_dirs(store).each do |dir|
        done_ts = last_done_ts(dir)
        if done_ts
          entries << [dir, done_ts] if done_ts >= window_start && done_ts <= now
        elsif completed.include?(File.basename(dir))
          skipped += 1
        end
      end
    end

    [entries.sort_by { |_dir, ts| ts }.map(&:first), skipped]
  end

  # D1/D7/D21/D22: one delivered screen per directory (oldest first, one
  # blank line apart), the roster last, and the skipped-count footer between
  # them when non-zero. `painter` is applied to each block SEPARATELY (D21):
  # a screen ScreenPaint cannot parse falls back to its own plain text
  # without touching its neighbours; the default is the identity function,
  # so a caller that never paints gets the plain screens verbatim. A
  # directory whose delivered screen cannot be rendered (O3.28) never sinks
  # the rest of the report.
  def self.render_session(dirs:, skipped:, store_root:, tag_reader: ->(_dir) { nil },
                           branch_reader: ->(_dir) { nil }, note: nil, changed: nil,
                           now: Time.now, painter: ->(text) { text })
    blocks = []
    blocks << note if note && !note.to_s.empty?

    if dirs.empty?
      blocks << "No intents delivered in this session."
    else
      dirs.each do |dir|
        blocks << begin
          render_delivered(intent_dir: dir, tag_reader: tag_reader, branch_reader: branch_reader).chomp
        rescue StandardError => e
          "## #{intent_id(dir)} · could not render (#{e.message})"
        end
      end
    end

    if skipped.positive?
      blocks << "#{skipped} completed intent#{skipped == 1 ? '' : 's'} skipped: no Done bookend in savepoint.md."
    end

    blocks << render_roster(store_root, changed: changed, now: now).chomp

    "#{blocks.map { |b| painter.call(b) }.join("\n\n")}\n"
  end

  # --- S10: the roadmap verb (intent 331c) -----------------------------------------
  #
  # `report-screen roadmap <roadmap.md> plan|state|delivered` - a roadmap's own three reports,
  # the counterpart to an intent's state/delivered. Every entry comes from RoadmapQueue's public
  # `roadmap` reader (D6/R1): no second parser here ever re-derives its grammar, its INDEX
  # reconciliation, or its frontier selection.

  ROADMAP_VERBS = %w[plan state delivered].freeze

  # D6/R17: the tier root for a roadmap path is the parent of `roadmaps/`, one extra parent when
  # the file sits under `roadmaps/archived/` - the SAME rule RoadmapSavepoint.index_path_for
  # uses (that method is private, so this is the rule's second, agreeing owner; a test pins them
  # together).
  def self.roadmap_tier_root(path)
    dir = File.dirname(path)
    dir = File.dirname(dir) if File.basename(dir) == "archived"
    File.dirname(dir)
  end

  def self.roadmap_default_template_path(verb)
    File.expand_path("../../templates/report-roadmap-#{verb}.md", __dir__)
  end

  # D6/R1: the parsed, INDEX-reconciled entries for one roadmap file, obtained from
  # RoadmapQueue's own public reader - never a second parser.
  def self.roadmap_entries(path:, store_root:)
    index_path = File.join(store_root, "INDEX.md")
    RoadmapQueue.new(roadmaps_dir: File.dirname(path), index_path: index_path).roadmap(path)
  end

  # R4/R15: the first sentence of `## Goal`, joined across wrapped source lines. Splits on a
  # period only (never IntentScreen.clause_and_rest's `[.;]` - a semicolon inside a real goal is
  # common and must survive, R15); a period with no following whitespace or end-of-string (a
  # version number like "2.0.0", never followed by a space mid-number) is never mistaken for a
  # sentence boundary (R4).
  def self.roadmap_goal(text)
    section = section_of(text, "## Goal").strip
    return NOT_RECORDED if section.empty?

    joined = section.lines.map(&:strip).join(" ").squeeze(" ")
    m = joined.match(/\A(.*?\.)(?=\s|\z)/)
    (m ? m[1] : joined).strip
  end

  # R16: the ledger's own entries when the paired `.savepoint.md` carries any; otherwise the
  # `## Log` lines classified through RoadmapSavepoint.classify_event (the same KEYWORD_TABLE,
  # no second vocabulary), each timestamped from its own Log line's date and time. A roadmap with
  # neither source (no ledger file, no classifiable Log line) answers `[]`, never an invented
  # event - callers reading it print `not recorded`.
  def self.roadmap_events(path)
    ledger = RoadmapSavepoint.ledger_entries(path)
    return ledger.sort_by { |t, _, _| t } if ledger.any?

    text = File.exist?(path) ? File.read(path) : nil
    return [] unless text

    section_of(text, "## Log").each_line.filter_map do |line|
      m = line.strip.match(RoadmapSavepoint::LOG_LINE)
      next nil unless m
      event = RoadmapSavepoint.classify_event(m[3])
      next nil unless event
      [Time.parse("#{m[1]}T#{m[2]}:00Z"), event, m[3].strip]
    end
  end

  # Every `## Log` line, classified for the delivered screen's Log table: an unclassifiable line
  # still renders, with `not recorded` in its Event cell (never dropped, unlike roadmap_events'
  # fallback, which only wants events it can act on).
  def self.roadmap_log_rows(text)
    section_of(text, "## Log").each_line.filter_map do |line|
      m = line.strip.match(RoadmapSavepoint::LOG_LINE)
      next nil unless m
      { when: human_time("#{m[1]}T#{m[2]}:00Z"), event: RoadmapSavepoint.classify_event(m[3]) || NOT_RECORDED, what: m[3].strip }
    end
  end

  # R7: idle unless the entry's own delivery lock is fresh as of `now:` - a stale lock (the
  # heartbeat older than the TTL) never masquerades as a live lead.
  def self.roadmap_lead(intent_dir, now:)
    return "idle" unless intent_dir
    lead_cell(intent_dir, now: now)
  end

  def self.roadmap_intent_dir(store_root, id)
    Dir.glob(File.join(store_root, "store", "#{id}--*")).sort.find { |d| IntentScreen.intent_dir?(d) }
  end

  def self.roadmap_entry_progress(dir)
    return NOT_RECORDED unless dir
    items = IntentScreen.checklist_items(dir)
    fields = IntentScreen.progress_fields(items)
    "#{fields['progress.bar']} #{fields['progress.done']} / #{fields['progress.total']}"
  end

  def self.roadmap_progress_bar(done, total)
    on = total.zero? ? 0 : (done * IntentScreen::BAR_WIDTH) / total
    (IntentScreen::ON * on) + (IntentScreen::OFF * (IntentScreen::BAR_WIDTH - on))
  end

  # "Batch" or "Wave" (singular): the entries table's own first column header (R3 - a legacy
  # Waves roadmap reads "Wave", never "Batch").
  def self.roadmap_batch_label(data)
    data[:grouping] == "Waves" ? "Wave" : "Batch"
  end

  def self.roadmap_all_entries(data)
    data[:batches].flat_map { |b| b[:entries] }
  end

  # --- plan (D2) ---------------------------------------------------------------

  def self.roadmap_plan_fields(text, data, events)
    all_entries = roadmap_all_entries(data)
    order = data[:batches].map { |b| b[:heading] }.join(" → ")
    created = events.empty? ? NOT_RECORDED : human_time(events.first[0].utc.iso8601)
    [
      ["Goal", roadmap_goal(text), ""],
      [data[:grouping], "#{data[:batches].length} #{data[:grouping].downcase}, #{all_entries.length} intents", ""],
      ["Order", order, ""],
      ["Created", created, ""],
    ]
  end

  def self.roadmap_plan_entries_table(data)
    label = roadmap_batch_label(data)
    rows = ["| #{label} | Graph ID | Intent | Status |", "| --- | --- | --- | --- |"]
    data[:batches].each do |batch|
      batch[:entries].each do |e|
        rows << "| #{escape(batch[:heading])} | #{escape(e[:id])} | #{escape(e[:text])} | #{escape(e[:status])} |"
      end
    end
    rows.join("\n")
  end

  # --- state (D3) ---------------------------------------------------------------

  def self.roadmap_state_fields(text, data, events, store_root, now)
    all_entries = roadmap_all_entries(data)
    total = all_entries.length
    delivered = all_entries.count { |e| e[:status] == "delivered" }
    bar = roadmap_progress_bar(delivered, total)

    frontier = data[:frontier]
    frontier_value = frontier ? frontier[:heading] : NOT_RECORDED
    frontier_note =
      if frontier.nil?
        ""
      elsif frontier[:in_flight].any?
        "in flight"
      else
        "queued"
      end

    delivering_value =
      if frontier && frontier[:in_flight].any?
        frontier[:in_flight].map do |e|
          dir = roadmap_intent_dir(store_root, e["id"])
          "#{e['id']} (#{roadmap_lead(dir, now: now)})"
        end.join(", ")
      else
        NOT_RECORDED
      end

    next_entry = all_entries.find { |e| e[:status] == "queued" }
    next_value = next_entry ? "#{next_entry[:id]} #{next_entry[:text]}".strip : NOT_RECORDED

    changed_value = events.empty? ? NOT_RECORDED : "#{events.last[1]} · #{human_time(events.last[0].utc.iso8601)}"

    [
      ["Goal", roadmap_goal(text), ""],
      ["Progress", "#{bar} #{delivered} / #{total}", ""],
      ["Frontier", frontier_value, frontier_note],
      ["Delivering", delivering_value, ""],
      ["Next", next_value, ""],
      ["Changed", changed_value, ""],
    ]
  end

  # RC4/spec.md defect 2: the Batches table carries the same Intent title column the plan
  # verb's own table already does (roadmap_plan_entries_table). The Intent cell spends
  # whatever the row's other cells leave it (W8a/W8b) through the ONE shared budget helper
  # (fit_row_cell) dashboard.rb's screen_fit_intent also spends by, computed PER ROW from that
  # row's own batch/id/status/progress/lead - never a cross-row max - so one long row's Intent
  # cell can never re-truncate another row's already-correct one (A5).
  def self.roadmap_state_entries_table(data, store_root, now)
    label = roadmap_batch_label(data)
    rows = ["| #{label} | Graph ID | Intent | Status | Progress | Lead |",
            "| --- | --- | --- | --- | --- | --- |"]
    data[:batches].each do |batch|
      batch[:entries].each do |e|
        dir = roadmap_intent_dir(store_root, e[:id])
        progress = roadmap_entry_progress(dir)
        lead = roadmap_lead(dir, now: now)
        others = [batch[:heading], e[:id], e[:status], progress, lead]
        intent_cell = fit_row_cell(e[:text], others)
        rows << "| #{escape(batch[:heading])} | #{escape(e[:id])} | #{escape(intent_cell)} | " \
                "#{escape(e[:status])} | #{escape(progress)} | #{escape(lead)} |"
      end
    end
    rows.join("\n")
  end

  # --- delivered (D4) ------------------------------------------------------------

  def self.roadmap_delivered_meta(data, events)
    all_entries = roadmap_all_entries(data)
    closed = events.reverse.find { |_t, event, _d| event == "closed" }
    closed_part = closed ? human_time(closed[0].utc.iso8601) : "in progress"

    merged = events.select { |_t, event, _d| event == "merged" }
    duration = events.empty? || merged.empty? ? NOT_RECORDED : format_duration((merged.last[0] - events.first[0]).to_i)

    "#{closed_part} · #{all_entries.length} intents · #{duration}"
  end

  # The regex RoadmapSavepoint::KEYWORD_TABLE pairs with an event word - read from the table
  # rather than copied, so the Merged cell's vocabulary never drifts from rebuild's own.
  def self.roadmap_savepoint_keyword_regex(event)
    RoadmapSavepoint::KEYWORD_TABLE.find { |_re, ev| ev == event }.first
  end

  # R10/R21/R22: the Merged cell reads a line only when the entry id is its SUBJECT - the first
  # whitespace-delimited token of the detail, never a whole word anywhere in it (R21: a real
  # ledger line names one entry's id as its subject and a SECOND entry's id in passing, and the
  # second entry has no merge line of its own to fill this row with). Among subject-matching
  # lines, one is read when the ledger's own event is `merged` OR its detail matches
  # KEYWORD_TABLE's merged pattern (R22: the appender sometimes files a real per-entry merge
  # under a different event word, `dispatched`, because the rest of the line was other news),
  # and refused when the event is `handoff` or the detail matches KEYWORD_TABLE's handoff
  # pattern - stricter than R10's original guarantee, never weaker. The sha is the first
  # hex-with-at-least-one-digit token of 7-40 characters in the matched line.
  def self.roadmap_merged_cell(id, events)
    merged_re = roadmap_savepoint_keyword_regex("merged")
    handoff_re = roadmap_savepoint_keyword_regex("handoff")

    line = events.find do |_t, event, detail|
      next false unless detail.to_s.strip.split(/\s+/).first == id
      next false if event == "handoff" || detail.to_s =~ handoff_re
      event == "merged" || detail.to_s =~ merged_re
    end
    return NOT_RECORDED unless line

    m = line[2].match(/\b(?=[0-9a-f]*\d)[0-9a-f]{7,40}\b/i)
    m ? m[0] : NOT_RECORDED
  end

  def self.roadmap_delivered_table(data, events)
    label = roadmap_batch_label(data)
    rows = ["| #{label} | Graph ID | Intent | Merged |", "| --- | --- | --- | --- |"]
    data[:batches].each do |batch|
      batch[:entries].each do |e|
        rows << "| #{escape(batch[:heading])} | #{escape(e[:id])} | #{escape(e[:text])} | " \
                "#{escape(roadmap_merged_cell(e[:id], events))} |"
      end
    end
    rows.join("\n")
  end

  def self.roadmap_log_table(text)
    log_rows = roadmap_log_rows(text)
    return NOT_RECORDED if log_rows.empty?

    rows = ["| When | Event | Detail |", "| --- | --- | --- |"]
    log_rows.each { |r| rows << "| #{escape(r[:when])} | #{escape(r[:event])} | #{escape(r[:what])} |" }
    rows.join("\n")
  end

  # --- render ---------------------------------------------------------------------

  # D6: `ReportScreen.render_roadmap(path:, verb:, store_root: nil, now: Time.now, template:
  # nil)`. No ENV, no git; `now:` is used only for lock freshness (R7). `store_root` defaults to
  # the derived tier root; `template` defaults to the installed-or-in-repo
  # `templates/report-roadmap-<verb>.md`.
  def self.render_roadmap(path:, verb:, store_root: nil, now: Time.now, template: nil)
    verb = verb.to_s
    raise ArgumentError, "verb must be one of #{ROADMAP_VERBS.join(', ')}, got #{verb.inspect}" unless ROADMAP_VERBS.include?(verb)

    store_root ||= roadmap_tier_root(path)
    text = File.read(path)
    data = roadmap_entries(path: path, store_root: store_root)
    events = roadmap_events(path)
    template ||= File.read(roadmap_default_template_path(verb))

    out = template.dup
    out = out.gsub("{{slug}}", data[:slug])

    case verb
    when "plan"
      out = out.gsub("{{fields.rows}}", state_rows(roadmap_plan_fields(text, data, events)).join("\n"))
      out = out.gsub("{{entries.table}}", roadmap_plan_entries_table(data))
    when "state"
      out = out.gsub("{{fields.rows}}", state_rows(roadmap_state_fields(text, data, events, store_root, now)).join("\n"))
      out = out.gsub("{{entries.table}}", roadmap_state_entries_table(data, store_root, now))
    when "delivered"
      out = out.gsub("{{meta}}", roadmap_delivered_meta(data, events))
      out = out.gsub("{{delivered.table}}", roadmap_delivered_table(data, events))
      out = out.gsub("{{log.table}}", roadmap_log_table(text))
    end

    fit_screen(out.gsub(/\n{3,}/, "\n\n"))
  end

  # --- S8: --ansi passthrough (D2) -----------------------------------------------
  #
  # 316a owns the ANSI renderer; 317 only wires a generic DI seam so this
  # module never blocks on 316a landing and never breaks when it does (row 77).
  # A renderer file, when present, is expected to define IntentScreenAnsi.paint
  # (one plain-text string in, one string out). Wiring the real contract 316a
  # ships is left to a follow-up step once that file exists (see checklist S14).
end
