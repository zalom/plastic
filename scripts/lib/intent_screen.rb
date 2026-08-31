# encoding: UTF-8
# frozen_string_literal: true
# IntentScreen (intent 316) - fills templates/intent-screen.md from one intent's
# record: the intent file, the tier's INDEX.md, savepoint.md and checklist.md.
# Every number on the screen comes from here so the session never writes one by
# eye. Pure: explicit paths in, a Markdown string out; no ENV, no Dir.pwd.
#
# Intent 316a fixed three defects the field code inherited into both the plain
# renderer and the ANSI renderer (scripts/lib/intent_screen_ansi.rb): the
# Insight row dumping a multi-clause remainder into the note column, an empty
# "What this means" heading rendering bold with nothing under it, and step
# text cut mid-sentence. `step_text`, `insight_fields` and `next_fields` are
# public so the ANSI renderer reuses the exact same trims (D3) rather than
# re-deriving them and drifting.
module IntentScreen
  BAR_WIDTH = 20
  ON = "█"
  OFF = "░"
  PLACEHOLDER_SENTINEL = "<!-- plastic:placeholder -->"
  SECTIONS = %w[Active Future Completed Abandoned].freeze
  ITEM_RE = /^\s*- \[([ xX])\]\s+(.*)$/
  # Em dash and en dash added (intent 316a O1e): a checklist item written
  # "S1 — text" (the em dash every checklist this intent writes, and the one a
  # reviewer reads, uses) kept its prefix under the old character class and
  # rendered "S1  [ open ]  S1 — text" on screen.
  STEP_PREFIX_RE = /\A(?:Step|S)\s*\d+\s*[-:·—–]\s*/i
  INSIGHT_RE = /\A(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s+·\s+\S+\s+·\s+.+?\s+—\s+(.+)\z/
  SAVEPOINT_RE = /\A(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s{2,}(\S+)\s{2,}(.+?)\s*\z/

  # Word-boundary truncation caps (intent 316a D3/O1a/O1c). Never a clause
  # trim: a clause trim on step text destroys a pinned `OPEN:` row
  # (test/intent_screen_test.rb:171-178) that a mid-sentence cut would eat.
  INSIGHT_VALUE_MAX = 72
  INSIGHT_NOTE_MAX = 96
  NEXT_VALUE_MAX = 72
  STEP_TEXT_MAX = 110

  MEANING_BLOCK_RE = /\n\*\*What this means\*\*\n\{\{meaning\}\}\n/
  CLOSE_BLOCK_RE = /\n\{\{close\}\}\s*\z/

  # Where a resume lands, from the ledger's last line (the boarding matrix).
  def self.landing_stage(stage, milestone)
    case stage
    when "Done" then "Done"
    when "What" then "Why"
    when "Why" then milestone.to_s.include?("spec.md") ? "How" : "Why"
    when "How" then milestone.to_s.include?("checklist.md") ? "Exec" : "How"
    when "Exec" then milestone.to_s.include?("outcome.md") ? "ready to complete" : "Exec"
    else "Why"
    end
  end

  def self.intent_dir?(dir)
    return false unless dir && File.directory?(dir)

    base = File.basename(dir)
    return false unless base.match?(/\A[0-9][0-9a-z]*--[\w-]+\z/)

    File.exist?(File.join(dir, "#{base}.md"))
  end

  def self.render(intent_dir:, store_root:, template:)
    base = File.basename(intent_dir)
    id = base.split("--", 2).first
    intent_text = File.read(File.join(intent_dir, "#{base}.md"))

    fields = {}
    fields.merge!(store_fields(store_root))
    status, title = index_fields(store_root, id)
    fields["status"] = status
    fields["status.note"] = status == "unlisted" ? "no INDEX.md line names this id" : "listed under ## #{status} in INDEX.md"
    fields["id"] = id
    fields["name"] = title || fallback_name(intent_text)
    fields.merge!(savepoint_fields(intent_dir, intent_text))
    items = checklist_items(intent_dir)
    fields.merge!(progress_fields(items))
    fields.merge!(next_fields(items, status, checklist_present: items_present?(intent_dir)))
    fields.merge!(insight_fields(intent_text))
    fields["steps.rows"] = steps_rows(items)
    fields["meaning"] = ""
    fields["close"] = ""

    out = template.dup
    # O1b: an empty "What this means" heading, or an empty {{close}}, must not
    # render at all — the heading alone was a bold line over nothing. Dropping
    # both moves the session's own bullets below the Steps table (D14).
    out = out.sub(MEANING_BLOCK_RE, "\n") if fields["meaning"].to_s.empty?
    out = out.sub(CLOSE_BLOCK_RE, "\n") if fields["close"].to_s.empty?
    fields.each { |k, v| out = out.gsub("{{#{k}}}", v.to_s) }
    out.gsub(/\n{3,}/, "\n\n")
  end

  # --- store ---------------------------------------------------------------------

  def self.store_fields(store_root)
    parent = File.basename(File.dirname(store_root))
    if parent == "projects"
      slug = File.basename(store_root)
      { "store" => "project:#{slug}", "store.note" => "the #{slug} project store" }
    else
      { "store" => "global", "store.note" => "the global store" }
    end
  end

  # --- INDEX.md -----------------------------------------------------------------

  def self.index_fields(store_root, id)
    path = File.join(store_root, "INDEX.md")
    return ["unlisted", nil] unless File.exist?(path)

    section = nil
    File.foreach(path) do |line|
      if line.start_with?("## ")
        name = line[3..].strip
        section = SECTIONS.include?(name) ? name : nil
        next
      end
      next unless section && line.strip.start_with?("- [")

      m = line.match(/\A\s*- \[#{Regexp.escape(id)}\s+[-—]\s+(.+?)\]\(/)
      return [section, m[1].strip] if m
    end
    ["unlisted", nil]
  end

  def self.fallback_name(intent_text)
    m = intent_text.match(/^intent:\s*["']?(.+?)["']?\s*$/)
    text = m ? m[1] : ""
    text.length > 60 ? "#{text[0, 57]}..." : text
  end

  # --- savepoint.md ---------------------------------------------------------------

  def self.savepoint_fields(intent_dir, intent_text)
    path = File.join(intent_dir, "savepoint.md")
    lines = File.exist?(path) ? File.readlines(path).map(&:strip).reject(&:empty?) : []
    last = lines.reverse.map { |l| l.match(SAVEPOINT_RE) }.compact.first
    unless last
      return { "stage" => "Why", "stage.note" => "no savepoint line yet",
               "savepoint" => "none", "savepoint.note" => "" }
    end

    ts, stage, milestone = last[1], last[2], last[3]
    landing = landing_stage(stage, milestone)
    delivered = lines.map { |l| l.match(SAVEPOINT_RE) }.compact.map { |m| m[2] }.uniq
    delivered &= %w[What Why How Exec]
    note = if landing == "Done"
             "delivered; the record is immutable"
           elsif landing == "ready to complete"
             "outcome.md is real; run the ending procedure"
           else
             "#{delivered.join(', ')} delivered; the work is open"
           end
    { "stage" => landing, "stage.note" => note,
      "savepoint" => "#{stage} · #{milestone}", "savepoint.note" => human_time(ts) }
  end

  def self.human_time(ts)
    m = ts.match(/\A(\d{4}-\d\d-\d\d)T(\d\d:\d\d)/)
    m ? "#{m[1]} #{m[2]} UTC" : ts
  end

  # --- checklist.md --------------------------------------------------------------

  def self.items_present?(intent_dir)
    path = File.join(intent_dir, "checklist.md")
    return false unless File.exist?(path)

    !File.read(path).lstrip.start_with?(PLACEHOLDER_SENTINEL)
  end

  def self.checklist_items(intent_dir)
    return [] unless items_present?(intent_dir)

    File.readlines(File.join(intent_dir, "checklist.md")).filter_map do |line|
      m = line.match(ITEM_RE)
      next unless m

      text = m[2].strip
      next if text == "..."

      { done: m[1] != " ", text: text.sub(STEP_PREFIX_RE, "") }
    end
  end

  def self.progress_fields(items)
    total = items.length
    done = items.count { |i| i[:done] }
    on = total.zero? ? 0 : (done * BAR_WIDTH) / total
    bar = (ON * on) + (OFF * (BAR_WIDTH - on))
    note = if total.zero?
             "no checklist yet"
           elsif done == total
             "all steps done"
           else
             "#{total - done} steps open"
           end
    { "progress.bar" => bar, "progress.done" => done.to_s, "progress.total" => total.to_s,
      "progress.note" => note }
  end

  # `escape:` (intent 316a O1d, default true) keeps the plain Markdown table's
  # pipe-escaping; the ANSI renderer, which never emits a table, passes
  # `escape: false` to get the raw value instead of a literal `\|`.
  def self.next_fields(items, status, checklist_present:, escape: true)
    return { "next" => "", "next.note" => "" } if %w[Completed Abandoned].include?(status)
    return { "next" => "write checklist.md", "next.note" => "How" } unless checklist_present

    idx = items.index { |i| !i[:done] }
    return { "next" => "", "next.note" => "all steps done" } unless idx

    head, = split_first_clause(items[idx][:text])
    head = truncate_words(head, NEXT_VALUE_MAX)
    head = IntentScreen.escape(head) if escape
    { "next" => "S#{idx + 1} · #{head}", "next.note" => "first open step" }
  end

  def self.steps_rows(items)
    return "| | | no steps yet |" if items.empty?

    items.each_with_index.map do |item, i|
      "| S#{i + 1} | #{item[:done] ? 'done' : 'open'} | #{escape(step_text(item[:text]))} |"
    end.join("\n")
  end

  # Public (intent 316a O1c) so the ANSI renderer trims step text identically:
  # word-boundary truncation only, never a clause trim, at STEP_TEXT_MAX.
  def self.step_text(text)
    truncate_words(text, STEP_TEXT_MAX)
  end

  def self.escape(text)
    text.gsub("|", "\\|")
  end

  # --- ## Insights ----------------------------------------------------------------

  def self.insight_fields(intent_text, escape: true)
    section = intent_text.split(/^## Insights\s*$/, 2)[1].to_s.split(/^## /, 2)[0].to_s
    entry = section.lines.map(&:strip).reverse.map { |l| l.match(INSIGHT_RE) }.compact.first
    return { "insight" => "none yet", "insight.note" => "" } unless entry

    ts, text = entry[1], entry[2].strip
    head, tail = split_first_clause(text)
    value = truncate_words(head, INSIGHT_VALUE_MAX)
    tail = tail.empty? ? "" : truncate_words(tail, INSIGHT_NOTE_MAX)
    note = tail.empty? ? human_time(ts) : "#{human_time(ts)} · #{tail}"
    if escape
      { "insight" => IntentScreen.escape(value), "insight.note" => IntentScreen.escape(note) }
    else
      { "insight" => value, "insight.note" => note }
    end
  end

  # First clause of `text`, and at most one following clause as the tail.
  # Anything past the second clause is discarded (intent 316a O1a): the old
  # behavior dumped the ENTIRE remainder into the note (an 800-character
  # real-world tail starting mid-list). Boundary is a `.` or `;` immediately
  # followed by whitespace-then-more or end of string, so "alpha.2" and "2.0"
  # are never mistaken for clause ends.
  def self.split_first_clause(text)
    head, rest = clause_and_rest(text)
    return [head, ""] unless rest

    second, more = clause_and_rest(rest)
    tail = more ? second : rest
    [head, tail]
  end

  # Returns [clause_without_terminal_punctuation, remainder_or_nil]. `nil` for
  # the remainder means either no boundary exists at all, or the boundary
  # sits at the absolute end of `text` (a single trailing clause with nothing
  # after it) — both cases where there is no SECOND clause to fold in.
  def self.clause_and_rest(text)
    m = text.match(/\A(.+?)[.;](\s+(.*)|\z)/m)
    return [text, nil] unless m

    remainder = m[2].to_s.strip
    remainder.empty? ? [m[1], nil] : [m[1], remainder]
  end

  # Word-boundary truncation with a trailing "…" when cut, never mid-word and
  # never a clause trim (intent 316a D3).
  def self.truncate_words(text, max)
    return text if text.length <= max
    return "…" if max <= 1

    cut = text[0, max - 1].rindex(" ")
    cut = max - 1 if cut.nil? || cut.zero?
    "#{text[0, cut].rstrip}…"
  end
end
