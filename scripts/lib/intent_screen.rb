# encoding: UTF-8
# frozen_string_literal: true
# IntentScreen (intent 316) - fills templates/intent-screen.md from one intent's
# record: the intent file, the tier's INDEX.md, savepoint.md, and checklist.md.
# Every number on the screen comes from here so the session never writes one by
# eye. Pure: explicit paths in, a Markdown string out; no ENV, no Dir.pwd.
module IntentScreen
  BAR_WIDTH = 20
  ON = "█"
  OFF = "░"
  PLACEHOLDER_SENTINEL = "<!-- plastic:placeholder -->"
  SECTIONS = %w[Active Future Completed Abandoned].freeze
  ITEM_RE = /^\s*- \[([ xX])\]\s+(.*)$/
  STEP_PREFIX_RE = /\A(?:Step|S)\s*\d+\s*[-:·]\s*/i
  INSIGHT_RE = /\A(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s+·\s+\S+\s+·\s+.+?\s+—\s+(.+)\z/
  SAVEPOINT_RE = /\A(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s{2,}(\S+)\s{2,}(.+?)\s*\z/
  # Intent 317, D6: field-2 tokens that are genuine lifecycle stages. A ledger
  # can also carry non-lifecycle lines (`Lock  takeover: ...`, and 317's own
  # `Review`/`Commit`); those must never be mistaken for the current stage.
  # Placed here, clear of STEP_PREFIX_RE above (316a edits that one).
  LIFECYCLE_STAGES = %w[What Why How Exec Done].freeze

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
    matched = lines.reverse.map { |l| l.match(SAVEPOINT_RE) }.compact
    last = matched.first
    unless last
      return { "stage" => "Why", "stage.note" => "no savepoint line yet",
               "savepoint" => "none", "savepoint.note" => "" }
    end

    # D6: the STAGE PICK is guarded to the last LIFECYCLE line (What/Why/How/
    # Exec/Done), so a trailing Lock/Review/Commit line cannot be mistaken for
    # the stage. The Savepoint field below still shows the TRUE last line,
    # whatever its kind - that is what a savepoint is.
    lifecycle_last = matched.find { |m| LIFECYCLE_STAGES.include?(m[2]) }
    stage_source = lifecycle_last || last

    ts, stage, milestone = last[1], last[2], last[3]
    landing = landing_stage(stage_source[2], stage_source[3])
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

  def self.next_fields(items, status, checklist_present:)
    return { "next" => "", "next.note" => "" } if %w[Completed Abandoned].include?(status)
    return { "next" => "write checklist.md", "next.note" => "How" } unless checklist_present

    idx = items.index { |i| !i[:done] }
    return { "next" => "", "next.note" => "all steps done" } unless idx

    head, = split_first_clause(items[idx][:text])
    { "next" => "S#{idx + 1} · #{escape(head)}", "next.note" => "first open step" }
  end

  def self.steps_rows(items)
    return "| | | no steps yet |" if items.empty?

    items.each_with_index.map do |item, i|
      "| S#{i + 1} | #{item[:done] ? 'done' : 'open'} | #{escape(item[:text])} |"
    end.join("\n")
  end

  def self.escape(text)
    text.gsub("|", "\\|")
  end

  # --- ## Insights ----------------------------------------------------------------

  def self.insight_fields(intent_text)
    section = intent_text.split(/^## Insights\s*$/, 2)[1].to_s.split(/^## /, 2)[0].to_s
    entry = section.lines.map(&:strip).reverse.map { |l| l.match(INSIGHT_RE) }.compact.first
    return { "insight" => "none yet", "insight.note" => "" } unless entry

    ts, text = entry[1], entry[2].strip
    head, tail = split_first_clause(text)
    note = tail.empty? ? human_time(ts) : "#{human_time(ts)} · #{tail}"
    { "insight" => escape(head), "insight.note" => escape(note) }
  end

  def self.split_first_clause(text)
    m = text.match(/\A(.+?)[.;](\s+.*|\z)/m)
    head = m ? m[1] : text
    tail = m ? m[2].to_s.strip : ""
    if head.length > 60
      cut = head[0, 60].rindex(" ") || 60
      tail = "#{head[cut..].strip} #{tail}".strip
      head = head[0, cut].strip
    end
    [head, tail]
  end
end
