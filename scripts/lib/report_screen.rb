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
require_relative "intent_screen"
require_relative "lock"

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

  # Markdown pipe-table data rows (header + separator skipped), each an array
  # of trimmed cell strings. Tolerates leading prose before the table.
  def self.table_rows(text)
    lines = text.to_s.lines.map(&:strip).select { |l| l.start_with?("|") }
    sep_idx = lines.index { |l| l.match?(/\A\|[\s:|-]+\|?\z/) }
    return [] unless sep_idx
    lines[(sep_idx + 1)..].map { |l| l.split("|", -1).map(&:strip)[1..-2].to_a }
  end

  # Every [heading_line, body] pair in a Markdown file, split on ANY heading
  # line (any level). Used by proven_by (D19) so a section's own matrix rows
  # are never confused with a sibling section's.
  def self.split_by_headings(text)
    sections = []
    heading = nil
    body = +""
    text.to_s.each_line do |line|
      if line.start_with?("#")
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

  # Rows 25-27: D19 - the label must appear as a standalone token in an action
  # file heading (any level); the count is the matched section's table rows only.
  def self.matching_action_heading(intent_dir, label)
    Dir.glob(File.join(intent_dir, "actions", "*.md")).sort.each do |path|
      split_by_headings(File.read(path)).each do |heading, body|
        tokens = heading.to_s.sub(/\A#+\s*/, "").split(/[^A-Za-z0-9]+/)
        return [heading, body] if tokens.include?(label)
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
    value && !value.to_s.empty? ? value.to_s : NOT_RECORDED
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

  def self.ship_row(text, intent_dir, tag_reader)
    line = text.to_s.lines.find { |l| l =~ /\bmerge(d)?\b/i && l =~ /\b[0-9a-f]{7,40}\b/ }
    sha = line && line.match(/\b([0-9a-f]{7,40})\b/)[1]
    version = tag_reader.call(intent_dir)
    return nil if sha.nil? && (version.nil? || version.to_s.empty?)
    ver_text = version && !version.to_s.empty? ? "v#{version.to_s.sub(/\Av/, '')}" : NOT_RECORDED
    sha_text = sha || NOT_RECORDED
    { kind: "ship", what: "#{sha_text} → alpha · #{ver_text}", source: "outcome.md; git tags" }
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

  def self.evidence_rows(intent_dir, tag_reader: ->(_dir) { nil })
    text = outcome_text(intent_dir)
    return [] unless text
    verification = section_of(text, "## Verification")

    rows = []
    rows << suite_row(verification)
    rows << red_row(verification)
    rows << (research_intent?(intent_dir) ? nil : ship_row(text, intent_dir, tag_reader))
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
    out.gsub(/\n{3,}/, "\n\n")
  end

  # --- roster (D7/D8) -------------------------------------------------------------

  def self.active_dirnames(index_path)
    return [] unless File.exist?(index_path)
    dirnames = []
    section = nil
    File.foreach(index_path) do |line|
      if line.start_with?("## ")
        section = line[3..].strip
        next
      end
      next unless section == "Active"
      m = line.match(%r{\(store/([^/]+)/})
      dirnames << m[1] if m
    end
    dirnames
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

  def self.lead(intent_dir)
    data = Lock.read(intent_dir)
    return "idle" unless data
    agent = data["owner_agent"].to_s
    session = data["owner_session"].to_s
    return "idle" if agent.empty? && session.empty?
    "#{agent.empty? ? 'unknown' : agent} · #{session[0, 8]}"
  rescue StandardError
    "idle"
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
    table = ["| Intent | Stage | Progress | Changed | Lead |", "| --- | --- | --- | --- | --- |"]
    entries.each do |e|
      text = intent_text(e[:dir]).to_s
      savepoint = IntentScreen.savepoint_fields(e[:dir], text)
      items = IntentScreen.checklist_items(e[:dir])
      progress = IntentScreen.progress_fields(items)
      ch = state_fields(intent_dir: e[:dir], store_root: store_root, changed: changed)[:rows].find { |l, _, _| l == "Changed" }[1]
      table << "| #{e[:id]} | #{savepoint['stage']} | #{progress['progress.bar']} #{progress['progress.done']} / #{progress['progress.total']} | #{escape(ch)} | #{lead(e[:dir])} |"
    end
    blocks = entries.map { |e| render_collapsed_block(e[:dir], store_root, changed: changed) }
    head_and_table = ([header, ""] + table).join("\n")
    # Each collapsed block already has its own internal "\n"; a blank line
    # separates block from block (design--delivery-reports.html:137-152),
    # so they read as distinct entries instead of running together.
    "#{head_and_table}\n\n#{blocks.join("\n\n")}\n"
  end

  # --- S6: the delivered verb ------------------------------------------------------

  def self.delivered_timestamp(intent_dir)
    lines = savepoint_lines(intent_dir)
    done = lines.reverse.find { |_ts, kind, _text| kind == "Done" }
    done ? human_time(done[0]) : NOT_RECORDED
  end

  def self.render_delivered(intent_dir:, tag_reader: ->(_dir) { nil })
    id = intent_id(intent_dir)
    name = title_for(intent_dir, default_store_root(intent_dir))
    ts = delivered_timestamp(intent_dir)
    m = mode(intent_dir)
    dur = duration(intent_dir)
    version = tag_reader.call(intent_dir)
    ver_text = version && !version.to_s.empty? ? "v#{version.to_s.sub(/\Av/, '')}" : NOT_RECORDED

    lines = []
    lines << "## ✔ #{id} · #{name} · delivered"
    lines << "#{ts} · #{m} · #{dur} · #{ver_text}"
    lines << ""
    lines << "**Asked**"
    lines << "  #{asked(intent_dir)}"
    lines << "  #{decision_note(intent_dir)}"
    lines << ""
    lines << "**Delivered**"
    lines << "| Row | What | Proven by |"
    lines << "| --- | --- | --- |"
    delivered_rows(intent_dir).each do |r|
      lines << "| #{r[:label]} | #{escape(r[:text])} | #{escape(proven_by(intent_dir, r[:label]))} |"
    end
    lines << ""
    lines << "**Evidence**"
    ev = evidence_rows(intent_dir, tag_reader: tag_reader)
    if ev.empty?
      # 317a S4 (matrix S4a): a header-only table (319's live rendering) says
      # nothing; the honest floor is the same phrase every other absent source
      # prints.
      lines << NOT_RECORDED
    else
      lines << "| Kind | What | Source |"
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
      lines << "| N | What | Why |"
      lines << "| --- | --- | --- |"
      needsyou.each { |r| lines << "| #{r[:n]} | #{escape(r[:what])} | #{escape(r[:why])} |" }
    end
    "#{lines.join("\n")}\n"
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
    "#{lines.join("\n")}\n"
  end

  # --- S8: --ansi passthrough (D2) -----------------------------------------------
  #
  # 316a owns the ANSI renderer; 317 only wires a generic DI seam so this
  # module never blocks on 316a landing and never breaks when it does (row 77).
  # A renderer file, when present, is expected to define IntentScreenAnsi.paint
  # (one plain-text string in, one string out). Wiring the real contract 316a
  # ships is left to a follow-up step once that file exists (see checklist S14).
  def self.maybe_paint(text, renderer_path:, enabled:)
    return text unless enabled
    return text unless renderer_path && File.exist?(renderer_path)

    begin
      require renderer_path
    rescue LoadError, StandardError
      return text
    end

    mod = Object.const_get(:IntentScreenAnsi) if Object.const_defined?(:IntentScreenAnsi)
    return text unless mod && mod.respond_to?(:paint)

    begin
      mod.paint(text)
    rescue StandardError
      text
    end
  end
end
