# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "date"
require "digest"
require "fileutils"
require_relative "node_file"
require_relative "graph_file"
require_relative "node_ledger"
require_relative "savepoint"
require_relative "insights"
require_relative "packet_wrapper"
require_relative "atomic_write"
require_relative "arm"

# NodePacket (intent 338, G5): builds a node's whole input from disk, the
# five blocks 327 section 8 fixed - the node, the ledger, the record, the
# knowledge hop, and where to work. n2 (this half) is the readers: every one
# of them a keyword seam with a real default, so the suite never shells out
# to git, never reads the owner's real store, and never sets an environment
# variable (spec D16). n3 adds assembly, the budget, and the packet's
# identity on top of the same file.
module NodePacket
  module_function

  DEFAULT_BUDGET_TOKENS = 8000
  DEFAULT_HOP_TOKENS = 2000
  MAX_LANDED_COMMITS = 10
  DECISIONS_KEEP = 5
  INSIGHTS_KEEP = 3

  # C7's "the executor stops without it" (spec D9), rendered whenever a
  # packet carries no lease and whenever the worktree Arm.worktree_block
  # reports is not provisioned.
  STOP_DIRECTIVE = "STOP: no lease is recorded for this node. Do not edit files or run any command until a runner dispatches this node with a holder, an expiry and a model."

  # Pinned so `packet=<sha>` is a function of the repo's history alone
  # (post-execution review finding B4): unpinned, `git log --stat` varies
  # with the terminal's COLUMNS (abbreviates paths, narrows the graph
  # column), the caller's `color.ui` (ANSI escapes land in the ledger data
  # block), and gitconfig's `format.pretty`/`log.date`/`log.showSignature`.
  GIT_LOG_FIXED_ARGS = %w[-c color.ui=false -c log.showSignature=false --no-pager log --no-color --pretty=fuller
                          --stat=200,200].freeze
  LANDED_COMMITS_MAX_BYTES = 8000

  def git_log_command(repo_dir:, files:)
    ["git", "-C", repo_dir.to_s, *GIT_LOG_FIXED_ARGS, "-n", MAX_LANDED_COMMITS.to_s, "--", *Array(files)]
  end

  # `COLUMNS` unset (Process.spawn/Open3 delete a var whose value is nil)
  # rather than merely left alone, so an interactive caller's terminal width
  # never reaches `git log --stat`'s column math.
  def git_log_env
    { "COLUMNS" => nil }
  end

  # `landed commits` is one of the three never-cut blocks (matrix 3.9), so an
  # unbounded `git log --stat` (ten verbose commit messages, say) could route
  # the whole packet straight to exit 4 with no cut able to help.
  def truncate_landed_commits(out)
    return out.to_s if out.to_s.bytesize <= LANDED_COMMITS_MAX_BYTES

    "#{out.byteslice(0, LANDED_COMMITS_MAX_BYTES)}\n[landed commits truncated at #{LANDED_COMMITS_MAX_BYTES} bytes]"
  end

  DEFAULT_GIT_RUNNER = lambda do |repo_dir:, files:|
    require "open3"
    out, _err, status = Open3.capture3(git_log_env, *git_log_command(repo_dir: repo_dir, files: files))
    status.success? ? truncate_landed_commits(out) : nil
  end

  PROJECT_LAYOUT_RE = %r{\A(.*)/projects/([^/]+)/store/[^/]+\z}.freeze

  # --- paths ---------------------------------------------------------------

  def savepoint_path(intent_dir)
    File.join(intent_dir, "savepoint.md")
  end

  def graph_path(intent_dir)
    File.join(intent_dir, "graph.md")
  end

  def find_node_path(intent_dir, node)
    dir = File.join(intent_dir, "nodes")
    exact = File.join(dir, "#{node}.md")
    return exact if File.exist?(exact)

    Dir.glob(File.join(dir, "#{node}--*.md")).sort.first
  end

  # --- block 1: the node (instruction) --------------------------------------

  # {ok:, error_kind:, text:, errors:, kind:, files:, budget:}. error_kind is
  # :unknown_node (no node file for this id, or the id is not declared in
  # graph.md - the runner's usage-error bucket, matrix 2.2), :unparsable (the
  # node file exists but NodeFile.parse rejects it, matrix 2.1), or
  # :unreadable_graph (graph.md itself does not parse).
  def node_block(intent_dir:, node:, node_reader: NodeFile.method(:parse), graph_reader: GraphFile.method(:parse))
    node_path = find_node_path(intent_dir, node)
    unless node_path
      return failure_block(:unknown_node, ["no node file for #{node.inspect}"])
    end

    parsed = node_reader.call(node_path)
    unless parsed[:ok]
      return failure_block(:unparsable, parsed[:errors])
    end

    graph = graph_reader.call(graph_path(intent_dir))
    unless graph[:ok]
      return failure_block(:unreadable_graph, graph[:errors])
    end

    unless graph[:graph][:nodes].include?(node.to_s)
      return failure_block(:unknown_node, ["node #{node} is not declared in graph.md"])
    end

    text = render_node_block(node: node, kind: parsed[:kind], files: parsed[:files], budget: parsed[:budget],
                              body: parsed[:body])
    { ok: true, error_kind: nil, text: text, errors: [], kind: parsed[:kind], files: parsed[:files] || [],
      budget: parsed[:budget] }
  end

  def failure_block(kind, errors)
    { ok: false, error_kind: kind, text: nil, errors: errors, kind: nil, files: nil, budget: nil }
  end
  private_class_method :failure_block

  def render_node_block(node:, kind:, files:, budget:, body:)
    lines = []
    lines << "# Node #{node}"
    lines << "kind: #{kind}"
    lines << "files: #{Array(files).join(', ')}"
    lines << "budget: #{budget}"
    lines << ""
    lines << body.to_s.strip
    "#{lines.join("\n")}\n"
  end

  # --- block 2: the ledger (retrieved data) ---------------------------------

  # Every transition line for `node`, in file order, torn lines marked as
  # such rather than silently dropped or read as evidence (matrix 2.4-2.6).
  def ledger_lines_block(intent_dir:, node:, entries: nil)
    entries ||= NodeLedger.entries(savepoint_path(intent_dir))
    node_entries = entries.select { |e| e[:subject] == node.to_s }
    return "(no transition lines for #{node})" if node_entries.empty?

    node_entries.map { |e| e[:torn] ? "[torn] #{e[:raw]}" : e[:raw] }.join("\n")
  end

  # Predecessors come from graph.md's edges (327 D41 removed them from the
  # node envelope, matrix 2.7); only an attributed, well-formed `done` line
  # counts as evidence the predecessor actually finished (matrix 2.8).
  # `entries` is an optional pre-read of the whole ledger (matrix 2.7a, B12
  # of the post-execution review): `node-transition` is a concurrent
  # appending writer, so re-reading `savepoint.md` once per predecessor let a
  # line landing mid-build make the Transitions, Lease and attempt number of
  # one packet disagree with each other. `build` reads once and threads the
  # same entries through every block; a direct caller with no entries to
  # share still gets a real default that reads the file itself.
  def predecessor_block(intent_dir:, node:, graph_reader: GraphFile.method(:parse), entries: nil)
    graph = graph_reader.call(graph_path(intent_dir))
    return "(no predecessors)" unless graph[:ok]

    targets = graph[:graph][:edges][node.to_s] || []
    return "(no predecessors)" if targets.empty?

    entries ||= NodeLedger.entries(savepoint_path(intent_dir))
    targets.map do |t|
      target_entries = entries.select { |e| e[:subject] == t }
      evidence = target_entries.select { |e| !e[:torn] && e[:attributed] && e[:state] == "done" }.last
      evidence ? "#{t}: done — #{evidence[:raw]}" : "#{t}: not yet done"
    end.join("\n")
  end

  def lease_present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :lease_present?

  def last_running_entry(node:, entries:)
    entries.select { |e| e[:subject] == node.to_s && !e[:torn] && e[:state] == "running" }.last
  end
  private_class_method :last_running_entry

  # Whether the packet renders no lease at all (matrix 2.11a, post-execution
  # review finding A1): neither a flag-supplied lease nor a recorded
  # `running` line for this node. `lease_block` itself only ever renders
  # `lease: none` for this case (spec D3: block 2 is retrieved data, and C7's
  # stop directive is instruction, so it can never live inside that data
  # block, on pain of being self-cancelling under the packet's own trust
  # rule). `build` uses this to decide whether the stop directive belongs in
  # block 5 instead, deduplicated against the worktree's own copy.
  def lease_missing?(node:, holder:, expires:, model:, entries:)
    return false if lease_present?(holder) || lease_present?(expires) || lease_present?(model)

    last_running_entry(node: node, entries: entries).nil?
  end

  # The lease from --holder/--expires/--model when given (matrix 2.9), else
  # the node's last `running` ledger line (matrix 2.10), else `lease: none`
  # (matrix 2.11) with no directive of any kind: the stop directive is
  # instruction (spec D3) and is rendered in block 5 by `build`, never here.
  def lease_block(intent_dir:, node:, holder: nil, expires: nil, model: nil, entries: nil)
    if lease_present?(holder) || lease_present?(expires) || lease_present?(model)
      return "lease: holder=#{holder} expires=#{expires} model=#{model}"
    end

    entries ||= NodeLedger.entries(savepoint_path(intent_dir))
    last = last_running_entry(node: node, entries: entries)
    return "lease: none" unless last

    f = last[:fields] || {}
    "lease: holder=#{f['holder']} expires=#{f['expires']} model=#{f['model']}"
  end

  # Landed commits after a reclaim (spec D14, C11). Never shells out to git
  # unless the node actually carries a `reclaimed` line (matrix 2.13); a
  # failing runner degrades to a note, never an exception (matrix 2.14).
  def landed_commits_block(intent_dir:, node:, files:, repo_dir:, git_runner: DEFAULT_GIT_RUNNER, entries: nil)
    entries ||= NodeLedger.entries(savepoint_path(intent_dir))
    node_entries = entries.select { |e| e[:subject] == node.to_s && !e[:torn] }
    return nil unless node_entries.any? { |e| e[:state] == "reclaimed" }
    return nil if Array(files).empty? || repo_dir.to_s.empty?

    begin
      out = git_runner.call(repo_dir: repo_dir, files: files)
      out.to_s.strip.empty? ? "landed commits: none found for #{files.join(', ')}" : out
    rescue StandardError => e
      "landed commits: unavailable (#{e.class}: #{e.message})"
    end
  end

  # --- block 3: the record (retrieved data) ---------------------------------

  # {ok:, intent:, decisions: [...], insights: [...], errors:}. Only the
  # three named sections are ever carried (matrix 2.15): `## Intent` in
  # full (the floor, spec D8), `### Decisions` (falling back to a top-level
  # `## Decisions` when the nested one is absent) split into list items, and
  # the last three `## Insights` entries (matrix 2.16), with the kind-aware
  # `### Findings` exclusion applied before entries are split (matrix 2.17,
  # 2.18, 2.18a).
  def record_block(intent_dir:, kind:)
    path = Savepoint.intent_file(intent_dir)
    return { ok: false, intent: nil, decisions: [], insights: [], errors: ["record file not found: #{path}"] } unless File.exist?(path)

    content = File.read(path)
    intent_text = section_at_level(content, 2, /\AIntent\z/i).to_s.strip
    decisions_text = section_at_level(content, 3, /\ADecisions\b/i)
    decisions_text = section_at_level(content, 2, /\ADecisions\b/i) if decisions_text.to_s.strip.empty?
    decisions = split_list_items(decisions_text.to_s)

    insights_text = section_at_level(content, 2, /\AInsights\z/i).to_s
    insights_text = strip_findings(insights_text) if kind.to_s == "verify"
    insights = split_insight_entries(insights_text).last(INSIGHTS_KEEP)

    { ok: true, intent: intent_text, decisions: decisions, insights: insights, errors: [] }
  end

  def record_sources(intent_dir)
    path = Savepoint.intent_file(intent_dir)
    return [] unless File.exist?(path)

    content = File.read(path)
    return [] unless content.start_with?("---")

    parts = content.split("---", 3)
    return [] if parts.length < 3

    fm = begin
      YAML.safe_load(parts[1], permitted_classes: [Date, Time])
    rescue StandardError
      nil
    end
    return [] unless fm.is_a?(Hash)

    Array(fm["sources"])
  end

  # --- block 4: the knowledge hop (retrieved data) --------------------------

  # One level, never transitive (matrix 2.19): each source's own `## Outcome`
  # and `### Decisions` (falling back to that source's spec.md `## Decisions`
  # when the record carries none, matrix 2.20a, spec D13). An unresolvable
  # source is noted, never raised (matrix 2.21). Capped at `hop_tokens`, with
  # a truncation note when it is cut (matrix 2.22); `hop_tokens` 0 disables
  # the hop entirely (matrix 2.23, spec D7/224's kill criterion).
  #
  # `hop=` on the running line is measured against this cap (C33, intent
  # 224's kill criterion), so the reported `tokens` must never overshoot it
  # by the truncation note's own cost (post-execution review finding C13):
  # the note's bytes are subtracted from the byte budget before slicing, and
  # the slice is trimmed to valid UTF-8 (never repaired) before it is
  # counted, because a raw `byteslice` can split a multi-byte character.
  # Trimming, not `String#scrub`, is what keeps the count honest: `scrub`
  # repairs an invalid tail by inserting a three-byte replacement character,
  # which can grow the slice back past the very budget it was cut to.
  def hop_block(store_dir:, sources:, hop_tokens: DEFAULT_HOP_TOKENS)
    return { text: nil, tokens: 0 } if hop_tokens.to_i <= 0 || Array(sources).empty?

    chunks = Array(sources).map { |src| hop_chunk(store_dir, src) }
    text = chunks.join("\n\n").scrub
    cap = hop_tokens.to_i
    tokens = PacketWrapper.estimate_tokens(text)
    if tokens > cap
      note = "\n[hop truncated at #{cap} tokens]"
      max_bytes = [(cap * 4) - note.bytesize, 0].max
      text = "#{safe_byteslice(text, max_bytes)}#{note}"
      tokens = PacketWrapper.estimate_tokens(text)
    end
    { text: text, tokens: tokens }
  end

  # Shrinks a byte slice (never grows it) until it is valid UTF-8, so a cut
  # that lands inside a multi-byte character is trimmed away rather than
  # repaired with a replacement character (post-execution review finding
  # C13). Bounded by `max_bytes` on every path: the result's bytesize never
  # exceeds what was asked for.
  def safe_byteslice(text, max_bytes)
    bytes = [max_bytes.to_i, 0].max
    slice = text.to_s.byteslice(0, bytes)
    while slice && !slice.valid_encoding? && bytes.positive?
      bytes -= 1
      slice = text.to_s.byteslice(0, bytes)
    end
    slice && slice.valid_encoding? ? slice : ""
  end
  private_class_method :safe_byteslice

  def hop_chunk(store_dir, source_id)
    source_dir = resolve_source_dir(store_dir, source_id)
    return "### #{source_id}\nunresolvable source: no directory for #{source_id.inspect}" unless source_dir

    record_path = Savepoint.intent_file(source_dir)
    content = File.exist?(record_path) ? File.read(record_path) : nil
    outcome = content ? section_at_level(content, 2, /\AOutcome\z/i).to_s.strip : ""
    decisions_text = content ? section_at_level(content, 3, /\ADecisions\b/i) : nil
    if decisions_text.to_s.strip.empty?
      spec_path = File.join(source_dir, "spec.md")
      spec_content = File.exist?(spec_path) ? File.read(spec_path) : nil
      # D13's fallback (post-execution review finding B10): `\b` here, to
      # match `record_block`'s own `### Decisions` pattern, which D12's
      # Findings rule already establishes tolerates a trailing qualifier on
      # the heading line. `\z` required an exact "Decisions" heading, so a
      # source whose spec.md carries "## Decisions (from intent Context)" or
      # "## Decisions Log" (eight specs in this store do) silently rendered
      # an empty hop instead of using the fallback D13 exists to provide.
      decisions_text = spec_content ? section_at_level(spec_content, 2, /\ADecisions\b/i) : nil
    end
    "### #{source_id}\n#### Outcome\n#{outcome}\n\n#### Decisions\n#{decisions_text.to_s.strip}"
  end
  private_class_method :hop_chunk

  # The record's and each hop source's real store-relative path (post-
  # execution review finding C15, spec D5a: "source is rendered
  # store-relative"): the literal constants "record" and "sources" were not
  # paths at all, defeating matrix row 1.3's reason for the attribute to
  # exist (telling the executor which file a paragraph came from).
  def record_source_path(intent_dir)
    path = Savepoint.intent_file(intent_dir)
    "#{File.basename(intent_dir)}/#{File.basename(path)}"
  end

  def hop_source_paths(store_dir, sources)
    Array(sources).map do |src|
      dir = resolve_source_dir(store_dir, src)
      dir ? "#{File.basename(dir)}/#{File.basename(Savepoint.intent_file(dir))}" : "#{src} (unresolved)"
    end.join(", ")
  end

  def resolve_source_dir(store_dir, source_id)
    exact = File.join(store_dir, source_id.to_s)
    return exact if File.directory?(exact)

    Dir.glob(File.join(store_dir, "#{source_id}--*")).select { |p| File.directory?(p) }.sort.first
  end
  private_class_method :resolve_source_dir

  # --- block 5: where to work (instruction) ---------------------------------

  def worktree_block(intent_dir:, worktree_reader: Arm.method(:worktree_block))
    info = worktree_reader.call(intent_dir: intent_dir)
    if info && info["provisioned"]
      "worktree: #{info['code']} (branch #{info['code_branch']})"
    else
      "worktree: none provisioned\n#{STOP_DIRECTIVE}"
    end
  end

  def default_project_reader(intent_dir)
    m = intent_dir.to_s.match(PROJECT_LAYOUT_RE)
    return nil unless m

    home, slug = m[1], m[2]
    path = File.join(home, "projects", slug, "project.yml")
    return nil unless File.exist?(path)

    # `permitted_classes` (post-execution review finding B3): the same bug
    # class `record_sources` already fixed once in 607e31e. Any project.yml
    # that gains a date-typed value (a `created:` field, say) silently
    # stripped the test command from every packet for that project, since
    # the rescue swallowed `Psych::DisallowedClass` and returned nil.
    data = begin
      YAML.safe_load(File.read(path), permitted_classes: [Date, Time])
    rescue StandardError
      nil
    end
    return nil unless data.is_a?(Hash)

    release = data["release"]
    return nil unless release.is_a?(Hash)

    verify = release["verify"]
    return nil unless verify.is_a?(String) && !verify.strip.empty?

    # A multi-line `verify` (post-execution review finding A2) is collapsed
    # to one line rather than refused: each of its own lines is joined with
    # "; ", the shell-sequencing separator, so "ruby bin/test\necho done"
    # reads as "ruby bin/test; echo done" instead of landing as extra raw
    # lines in block 5 (instruction, un-wrapped) where one of those lines
    # could happen to be a complete data marker.
    verify.split("\n").map(&:strip).reject(&:empty?).join("; ")
  end

  # `files` (intent 355, n4, D5): a node's own declared `*_test.rb` files
  # name the only test command the executor needs - `bin/test --only <those
  # files>` - so it never has to invent one or fall back to the project's
  # generic `release.verify`. A node that declares no test files (a docs-only
  # node, say) still falls back to `project_reader` exactly as before.
  def test_command_block(intent_dir:, files: [], project_reader: method(:default_project_reader))
    named = Array(files).select { |f| f.to_s.end_with?("_test.rb") }
    return "test command: ruby bin/test --only #{named.join(' ')}" if named.any?

    cmd = project_reader.call(intent_dir)
    cmd ? "test command: #{cmd}" : "test command: none recorded in the project record"
  end

  # `lease_missing` (post-execution review finding A1) hoists C7's stop
  # directive here, block 5 (instruction, spec D3), whenever the packet
  # carries no lease. `worktree_block` already renders its own copy when the
  # worktree is unprovisioned; the two conditions often fire together, so a
  # directive already present is never repeated.
  #
  # `call_cap` (intent 355, n2, D2): one sentence naming this attempt's tool
  # call cap and the return it hits at, so the executor learns the number
  # from the packet it starts with, never from a denied call mid-edit
  # (matrix 2.4). nil (a caller that names no cap) renders nothing here.
  def where_to_work_block(intent_dir:, worktree_reader: Arm.method(:worktree_block),
                           project_reader: method(:default_project_reader), lease_missing: false, call_cap: nil,
                           files: [])
    wt = worktree_block(intent_dir: intent_dir, worktree_reader: worktree_reader)
    parts = [wt, test_command_block(intent_dir: intent_dir, files: files, project_reader: project_reader)]
    parts << STOP_DIRECTIVE if lease_missing && !wt.include?(STOP_DIRECTIVE)
    parts << call_cap_sentence(call_cap) if call_cap
    parts.join("\n")
  end

  def call_cap_sentence(call_cap)
    "call budget: this attempt may make at most #{call_cap} tool calls; past that a hook denies the " \
      "next one, so commit what is green and return failed_verification reason=call_budget."
  end

  # --- section and list parsing (shared) -------------------------------------

  # The body of the FIRST heading, at exactly `level` `#` characters, whose
  # text (after the marks) matches `title_re`, up to (excluding) the next
  # heading at `level` or shallower, or EOF. Fence-aware via
  # NodeFile.each_fence_line, so a fenced example line starting with `#`
  # never ends a section early. nil when no such heading exists.
  def section_at_level(content, level, title_re)
    in_section = false
    found = false
    body_lines = []
    NodeFile.each_fence_line(content.to_s) do |line, fenced|
      if fenced
        body_lines << line if in_section
        next
      end

      m = line.match(/\A(#+)[ \t]+(.*?)\s*\z/)
      if in_section
        if m && m[1].length <= level
          in_section = false
        else
          body_lines << line
        end
      elsif m && m[1].length == level && m[2] =~ title_re
        in_section = true
        found = true
      end
    end
    found ? body_lines.join : nil
  end

  # A Markdown bullet list split into items: a line starting with `- ` opens
  # a new item, and every following line up to the next such line is that
  # item's continuation (spec: Decisions cut to "the last five", matrix
  # 3.8, which only makes sense over list items, not raw lines).
  def split_list_items(text)
    items = []
    current = nil
    text.to_s.each_line do |line|
      if line.match?(/\A-\s/)
        items << current if current
        current = +line
      elsif current
        current << line
      end
    end
    items << current if current
    items
  end

  # `## Insights` entries split by `Insights::PREFIX_RE` (matrix 2.16a): a
  # continuation line (one that does not itself open a new prefixed entry)
  # is appended to the entry it follows, never counted as its own entry.
  # Text before the first prefixed line (the scaffold placeholder, matrix
  # 2.16b) is dropped rather than treated as an entry.
  def split_insight_entries(text)
    entries = []
    current = nil
    text.to_s.each_line do |line|
      if line.match?(Insights::PREFIX_RE)
        entries << current if current
        current = +line
      elsif current
        current << line
      end
    end
    entries << current if current
    entries
  end

  # Remove any `### Findings` subsection (tolerating a trailing qualifier on
  # the heading line, matrix 2.18a) from `text`, up to the next heading at
  # level 3 or shallower, or EOF. Anchored to whatever section `text` already
  # is (the caller passes only the `## Insights` body), so a `### Findings`
  # living under a DIFFERENT section (matrix 2.18a's intent-109 case, `##
  # Context`) is never reached because it is never part of `text`.
  def strip_findings(text)
    lines = text.to_s.each_line.to_a
    out = []
    i = 0
    while i < lines.length
      m = lines[i].match(/\A(#+)[ \t]+(.*?)\s*\z/)
      if m && m[1].length == 3 && m[2] =~ /\AFindings\b/i
        i += 1
        while i < lines.length
          m2 = lines[i].match(/\A(#+)[ \t]+/)
          break if m2 && m2[1].length <= 3

          i += 1
        end
        next
      end
      out << lines[i]
      i += 1
    end
    out.join
  end

  # ===========================================================================
  # n3: assembly, the budget, and the packet's identity
  # ===========================================================================

  # Block labels/sources for the wrapped (data) blocks, spec D3.
  LEDGER_LABEL = "ledger"
  RECORD_LABEL = "record"
  HOP_LABEL = "knowledge hop"

  # The whole "ledger" data block (spec block 2): the node's own transition
  # lines, its predecessors' evidence, its lease, and any landed commits
  # after a reclaim.
  def full_ledger_text(intent_dir:, node:, files:, holder:, expires:, model:, repo_dir:, git_runner:, entries: nil)
    entries ||= NodeLedger.entries(savepoint_path(intent_dir))
    landed = landed_commits_block(intent_dir: intent_dir, node: node, files: files, repo_dir: repo_dir,
                                   git_runner: git_runner, entries: entries)
    parts = [
      "### Transitions",
      ledger_lines_block(intent_dir: intent_dir, node: node, entries: entries),
      "",
      "### Predecessors",
      predecessor_block(intent_dir: intent_dir, node: node, entries: entries),
      "",
      "### Lease",
      lease_block(intent_dir: intent_dir, node: node, holder: holder, expires: expires, model: model,
                  entries: entries),
    ]
    if landed
      parts << ""
      parts << "### Landed commits"
      parts << landed
    end
    parts.join("\n")
  end

  # The record's Intent/Decisions/Insights rendered as one payload, over
  # whatever (possibly already-cut) decisions/insights arrays the cut ladder
  # is currently holding.
  def render_record_text(intent:, decisions:, insights:)
    parts = ["## Intent", intent.to_s.strip, ""]
    parts << "## Decisions"
    parts << (decisions.empty? ? "(none)" : decisions.join.rstrip)
    parts << ""
    parts << "## Insights"
    parts << (insights.empty? ? "(none)" : insights.join.rstrip)
    "#{parts.join("\n")}\n"
  end

  # One packet, node and where-to-work as plain instruction text, ledger,
  # record and (when present) hop wrapped as labeled data sharing ONE
  # boundary token computed over their raw payloads (spec D2-D4, matrix
  # 3.1-3.3).
  #
  # Blocks 1 and 5 are raw-interpolated (spec D3: instruction, not data), but
  # that trust does not reach a `release.verify` a project.yml can carry
  # (post-execution review finding A2): a line that is, on its own, a
  # complete data marker is disarmed by `PacketWrapper.neutralize_marker_lines`
  # before it ever reaches the packet, so a forged marker cannot open a
  # block outside the wrapper's own boundary. `record_source`/`hop_source`
  # (finding C15) are the record's and the hop sources' real store-relative
  # paths, never the placeholder label "record"/"sources".
  def render_packet(node_text:, ledger_text:, intent_text:, decisions:, insights:, hop:, where_text:,
                     record_source: "record", hop_source: "sources")
    record_text = render_record_text(intent: intent_text, decisions: decisions, insights: insights)
    hop_text = hop && hop[:text]

    payloads = [ledger_text, record_text]
    payloads << hop_text if hop_text
    token = PacketWrapper.boundary_token(payloads)

    node_text_safe = PacketWrapper.neutralize_marker_lines(node_text.to_s)
    where_text_safe = PacketWrapper.neutralize_marker_lines(where_text.to_s)

    # Normalized through `attr_safe` exactly as `wrap` normalizes the marker
    # attributes it writes (post-execution review finding A2's integrity
    # check): comparing the raw `record_source`/`hop_source` against what
    # `unwrap` reads back off the rendered marker line raised on every nil
    # source, because `attr_safe(nil)` renders as `""`, not `"nil".to_s`.
    wrapped_specs = [
      { label: PacketWrapper.attr_safe(LEDGER_LABEL), source: PacketWrapper.attr_safe("savepoint.md") },
      { label: PacketWrapper.attr_safe(RECORD_LABEL), source: PacketWrapper.attr_safe(record_source) },
    ]
    wrapped_specs << { label: PacketWrapper.attr_safe(HOP_LABEL), source: PacketWrapper.attr_safe(hop_source) } if hop_text

    parts = [node_text_safe.rstrip, ""]
    parts << PacketWrapper.wrap(ledger_text, label: LEDGER_LABEL, source: "savepoint.md", token: token).rstrip
    parts << ""
    parts << PacketWrapper.wrap(record_text, label: RECORD_LABEL, source: record_source, token: token).rstrip
    parts << ""
    if hop_text
      parts << PacketWrapper.wrap(hop_text, label: HOP_LABEL, source: hop_source, token: token).rstrip
      parts << ""
    end
    parts << where_text_safe.rstrip
    rendered = "#{parts.join("\n")}\n"

    assert_packet_integrity!(rendered, wrapped_specs)
    rendered
  end

  # The trust boundary's own invariant (post-execution review finding A2):
  # the finished packet must unwrap to exactly the data blocks that were
  # wrapped, same count, same labels, same sources, in order. This is what
  # the escaping rule and the marker-line neutralization pass are FOR, so the
  # check belongs here, not only in a test that could rot independently of
  # the code it is meant to guard.
  def assert_packet_integrity!(rendered, wrapped_specs)
    actual = PacketWrapper.unwrap(rendered).map { |b| { label: b[:label], source: b[:source] } }
    return if actual == wrapped_specs

    raise "node packet integrity check failed: expected #{wrapped_specs.inspect}, got #{actual.inspect}"
  end
  private_class_method :assert_packet_integrity!

  def render_from_state(state)
    render_packet(node_text: state[:node_text], ledger_text: state[:ledger_text], intent_text: state[:intent_text],
                  decisions: state[:decisions], insights: state[:insights], hop: state[:hop],
                  where_text: state[:where_text], record_source: state[:record_source] || "record",
                  hop_source: state[:hop_source] || "sources")
  end
  private_class_method :render_from_state

  def estimate_rendered_tokens(rendered)
    PacketWrapper.estimate_tokens(rendered)
  end

  # The C28 cut ladder: drop the hop whole, then cut Insights to the last
  # one, then cut Decisions to the last five - applied only as far as
  # needed, and only when a step actually shrinks the rendered bytes (matrix
  # 3.23: a cut that would not reduce the render is skipped rather than
  # counted as applied). The node, ledger and where-to-work blocks are never
  # touched (matrix 3.9) because nothing here ever rewrites those keys.
  def apply_cut_ladder(state, budget_tokens)
    cuts = []
    current = state
    rendered = render_from_state(current)
    tokens = estimate_rendered_tokens(rendered)
    return [rendered, tokens, cuts] if tokens <= budget_tokens

    if current[:hop] && current[:hop][:text]
      candidate_state = current.merge(hop: { text: nil, tokens: 0 })
      candidate = render_from_state(candidate_state)
      if candidate.bytesize < rendered.bytesize
        current, rendered = candidate_state, candidate
        tokens = estimate_rendered_tokens(rendered)
        cuts << :hop
      end
    end
    return [rendered, tokens, cuts] if tokens <= budget_tokens

    if current[:insights].length > 1
      candidate_state = current.merge(insights: current[:insights].last(1))
      candidate = render_from_state(candidate_state)
      if candidate.bytesize < rendered.bytesize
        current, rendered = candidate_state, candidate
        tokens = estimate_rendered_tokens(rendered)
        cuts << :insights
      end
    end
    return [rendered, tokens, cuts] if tokens <= budget_tokens

    if current[:decisions].length > DECISIONS_KEEP
      candidate_state = current.merge(decisions: current[:decisions].last(DECISIONS_KEEP))
      candidate = render_from_state(candidate_state)
      if candidate.bytesize < rendered.bytesize
        current, rendered = candidate_state, candidate
        tokens = estimate_rendered_tokens(rendered)
        cuts << :decisions
      end
    end

    [rendered, tokens, cuts]
  end
  private_class_method :apply_cut_ladder

  # Which never-cut-or-already-at-floor block is largest, so a refusal names
  # what to shorten (matrix 3.24) rather than just saying "too big".
  def name_oversized_block(state)
    record_text = render_record_text(intent: state[:intent_text], decisions: state[:decisions],
                                      insights: state[:insights])
    candidates = {
      "node" => state[:node_text],
      "ledger" => state[:ledger_text],
      "record" => record_text,
      "where to work" => state[:where_text],
    }
    name, text = candidates.max_by { |_, t| PacketWrapper.estimate_tokens(t.to_s) }
    [name, PacketWrapper.estimate_tokens(text.to_s)]
  end
  private_class_method :name_oversized_block

  def lease_flag_given?(holder)
    lease_present?(holder)
  end
  private_class_method :lease_flag_given?

  # C21: the number of `running` lines already recorded for `node`, plus one
  # when a lease is being supplied by flag (a NEW dispatch), floored at 1.
  # Minor 5: a torn `running` line (missing holder=/expires=/input=/model=)
  # is skipped here exactly as ReadySet.attempts_count already skips it -
  # counting it desynchronizes this attempt number from the extensions file
  # a live node's own `packets/<node>--a<N>.extensions` names, since that
  # file is keyed by the attempt sweep computed off the SAME filtered count.
  def compute_attempt_number(intent_dir:, node:, lease_flag_given:, entries: nil)
    entries ||= NodeLedger.entries(savepoint_path(intent_dir))
    count = entries.count { |e| !e[:torn] && e[:subject] == node.to_s && e[:state] == "running" }
    [count + (lease_flag_given ? 1 : 0), 1].max
  end

  def packet_path(intent_dir:, node:, attempt:)
    File.join(intent_dir, "packets", "#{node}--a#{attempt}.packet")
  end

  def summary_line(result)
    "path=#{result[:path]} sha=#{result[:sha]} tokens=#{result[:tokens]} hop_tokens=#{result[:hop_tokens]} " \
      "attempt=#{result[:attempt]}"
  end

  def running_command(intent_dir:, node:, sha:, hop_tokens:)
    "node-transition #{intent_dir} --node #{node} --state running --field input=#{sha} --field hop=#{hop_tokens}"
  end

  def needs_decision_command(intent_dir:, node:, question:)
    escaped = question.to_s.gsub("\\", "\\\\\\\\").gsub('"', "\\\"")
    "node-transition #{intent_dir} --node #{node} --state needs_decision --field question=\"#{escaped}\""
  end

  # Build one node's whole packet from disk (spec D1). Returns
  # {ok:, exit_code:, path:, sha:, tokens:, hop_tokens:, attempt:,
  # cuts_applied:, running_command:, errors:} on success, or
  # {ok: false, exit_code:, errors:, needs_decision_command: (on overflow)}
  # on refusal. Exit codes follow the node-transition family (spec D17): 2
  # usage (unknown node), 3 unreadable/unparsable graph, node file or
  # record, 4 overflow past the third cut, 5 an existing attempt whose bytes
  # differ.
  # M7/row 10.9: `budget_tokens: nil` (rather than DEFAULT_BUDGET_TOKENS)
  # is how a caller says "no override" - the fallback below then reaches for
  # the node block's OWN declared `budget:` before ever touching the
  # shipped default, so a caller that never learned about a node's budget
  # (the CLI, another future caller) still gets it, not just the one path
  # RunnerDispatch explicitly threads it through (row 10.8).
  def build(intent_dir:, node:, budget_tokens: nil, hop_tokens: DEFAULT_HOP_TOKENS,
            holder: nil, expires: nil, model: nil, attempt: nil, out: nil, force: false,
            renamer: File.method(:rename), git_runner: DEFAULT_GIT_RUNNER,
            worktree_reader: Arm.method(:worktree_block), project_reader: method(:default_project_reader),
            call_cap: nil)
    intent_dir = File.expand_path(intent_dir)

    nb = node_block(intent_dir: intent_dir, node: node)
    unless nb[:ok]
      return { ok: false, exit_code: nb[:error_kind] == :unknown_node ? 2 : 3, errors: nb[:errors] }
    end

    budget_tokens = (budget_tokens || nb[:budget] || DEFAULT_BUDGET_TOKENS).to_i

    record = record_block(intent_dir: intent_dir, kind: nb[:kind])
    return { ok: false, exit_code: 3, errors: record[:errors] } unless record[:ok]

    repo_dir = begin
      info = worktree_reader.call(intent_dir: intent_dir)
      info && info["code"]
    rescue StandardError
      nil
    end

    # Read the ledger once and thread it through every block that consults
    # it (post-execution review finding B12): `node-transition` is a
    # concurrent appending writer, so re-reading `savepoint.md` once per
    # block risked a line landing mid-build and making the Transitions,
    # Lease and attempt number of one packet disagree with each other.
    entries = NodeLedger.entries(savepoint_path(intent_dir))

    ledger_text = full_ledger_text(intent_dir: intent_dir, node: node, files: nb[:files], holder: holder,
                                    expires: expires, model: model, repo_dir: repo_dir, git_runner: git_runner,
                                    entries: entries)

    store_dir = File.dirname(intent_dir)
    sources = record_sources(intent_dir)
    hop_full = hop_block(store_dir: store_dir, sources: sources, hop_tokens: hop_tokens)

    # Finding A1: the stop directive belongs in block 5 (instruction)
    # whenever the packet carries no lease at all, never inside block 2's
    # ledger data (spec D3's self-cancellation risk).
    missing_lease = lease_missing?(node: node, holder: holder, expires: expires, model: model, entries: entries)
    where_text = where_to_work_block(intent_dir: intent_dir, worktree_reader: worktree_reader,
                                      project_reader: project_reader, lease_missing: missing_lease,
                                      call_cap: call_cap, files: nb[:files])

    state = {
      node_text: nb[:text], ledger_text: ledger_text, intent_text: record[:intent],
      decisions: record[:decisions], insights: record[:insights], hop: hop_full, where_text: where_text,
      # Finding C15: the record's and the hop sources' real store-relative
      # paths, never the placeholder labels "record"/"sources".
      record_source: record_source_path(intent_dir), hop_source: hop_source_paths(store_dir, sources),
    }

    rendered, tokens, cuts_applied = apply_cut_ladder(state, budget_tokens)

    if tokens > budget_tokens
      final_state = state.merge(
        hop: cuts_applied.include?(:hop) ? { text: nil, tokens: 0 } : state[:hop],
        insights: cuts_applied.include?(:insights) ? state[:insights].last(1) : state[:insights],
        decisions: cuts_applied.include?(:decisions) ? state[:decisions].last(DECISIONS_KEEP) : state[:decisions],
      )
      oversized_name, oversized_tokens = name_oversized_block(final_state)
      question = "packet for #{node} is #{tokens} tokens after every cut, over the #{budget_tokens}-token " \
                 "budget; #{oversized_name} alone is #{oversized_tokens} tokens, shorten it"
      return {
        ok: false, exit_code: 4, tokens: tokens,
        needs_decision_command: needs_decision_command(intent_dir: intent_dir, node: node, question: question),
        errors: ["overflow: #{oversized_name} is #{oversized_tokens} tokens over the #{budget_tokens}-token budget"],
      }
    end

    attempt_n = attempt || compute_attempt_number(intent_dir: intent_dir, node: node,
                                                   lease_flag_given: lease_flag_given?(holder), entries: entries)
    path = out ? File.expand_path(out) : packet_path(intent_dir: intent_dir, node: node, attempt: attempt_n)
    FileUtils.mkdir_p(File.dirname(path))

    if File.exist?(path)
      existing = File.binread(path)
      if existing == rendered
        # Rebuilding an unchanged attempt is a no-op (spec D11): the file on
        # disk already IS these exact bytes.
      elsif force
        AtomicWrite.write(path, rendered, renamer: renamer)
      else
        return { ok: false, exit_code: 5, errors: ["attempt file exists with different bytes: #{path}"] }
      end
    else
      AtomicWrite.write(path, rendered, renamer: renamer)
    end

    sha = Digest::SHA256.hexdigest(File.binread(path))[0, 12]
    hop_tokens_measured = cuts_applied.include?(:hop) ? 0 : hop_full[:tokens].to_i

    {
      ok: true, exit_code: 0, path: path, sha: sha, tokens: tokens, hop_tokens: hop_tokens_measured,
      attempt: attempt_n, cuts_applied: cuts_applied,
      running_command: running_command(intent_dir: intent_dir, node: node, sha: sha, hop_tokens: hop_tokens_measured),
      errors: [],
    }
  end
end
