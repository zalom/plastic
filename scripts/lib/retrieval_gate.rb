# encoding: UTF-8
# frozen_string_literal: true

require_relative "bridge"

# RetrievalGate — the single, pure decision for Lever 2 of intent 84, redesigned
# operation-based in intent 89a.
#
# Given an agent tool call (Bash/Read/Grep/Glob) and injected capability signals,
# it decides whether to BLOCK the call (returning a redirect-to-QMD reason String)
# or ALLOW it (returning nil). All capability/freshness signals are injected by the
# caller (the hook); this module shells out to nothing, reads no globals, and runs
# no binaries. Mirrors bridge.rb's decision-fn convention (reason String to block,
# nil to allow).
#
# Operation-based policy (intent 89, ## Redesign):
#   - The gate distinguishes DISCOVERY (content search) from READING a known target.
#   - Only CONTENT SEARCH over store markdown is hard-gated -> QMD.
#   - Reading a known target (Read, cat/head/tail) and structural discovery (Glob,
#     find, ls) are ALWAYS allowed, including over the store.
#   - Code navigation is a soft prompt MANDATE (PowerTools / UserPromptSubmit), not a
#     hard gate here. Content grep over code is allowed (Serena cannot grep strings).
#
# Content-search vectors (the only ones that can be gated):
#   - the Grep tool (its `path` search root)
#   - bash `grep`/`rg`/`ag` (their path args; the first bareword is the PATTERN)
#
# QMD enforcement is BINARY (no advisory tier):
#   - store-md content search: QMD detected+fresh -> BLOCK; detected+stale -> fire
#     reindex, ALLOW this turn; absent/broken -> ALLOW (the hook warns on broken).
#
# Bypass: a TRAILING `# qmd-ok` shell comment on a Bash command (not a substring; a
# quoted/echoed occurrence does not bypass). It is the auditable seam for "I tried
# discovery and it did not serve me" (empty, low, or wrongly-scored results).
#
# Scope: only the agent's own tool calls. Ruby `File.read` inside scripts is invisible
# to a PreToolUse hook and is explicitly out of scope (no exemptions).
module RetrievalGate
  module_function

  # A `# qmd-ok` token that is a real TRAILING shell comment, after stripping a
  # trailing newline. The token must be preceded by whitespace (or start the
  # command) and run to end-of-string. `echo "# qmd-ok"` does NOT match: the token
  # there is followed by a closing quote, not end-of-string.
  BYPASS_RE = /(?:\A|\s)#\s*qmd-ok\s*\z/.freeze

  # Bash utilities that perform CONTENT SEARCH (scan file CONTENT for a pattern).
  # These are the only bash read-vectors that can be gated; readers (cat/head/tail)
  # and structural tools (find/ls) are never gated.
  CONTENT_SEARCH_UTILS = %w[grep rg ag].freeze

  # Decide. Returns nil to ALLOW, or a reason String to BLOCK.
  #   capabilities: { qmd:, qmd_fresh: } (booleans).
  #   reindex: no-arg callable fired once when a QMD-class target is STALE.
  # When bypassed, returns nil and (if given) yields :bypass to the optional block
  # so the caller can log it.
  def decision(tool_name:, tool_input:, plastic_home:, cwd:,
               capabilities:, reindex: -> {})
    targets = extract_targets(tool_name, tool_input, cwd: cwd)
    return nil if targets.empty?

    if bypass?(tool_name, tool_input)
      yield(:bypass) if block_given?
      return nil
    end

    stale_seen = false
    targets.each do |path|
      next unless classify(path, plastic_home: plastic_home) == :qmd

      if capabilities[:qmd] && capabilities[:qmd_fresh]
        return qmd_reason(path)
      elsif capabilities[:qmd] # present but stale
        stale_seen = true
      end
      # absent/broken -> allow this target
    end

    reindex.call if stale_seen
    nil
  end

  # --- classification ---

  # Operation-based: the store tree is the only gated class (content search whose
  # target is at/under a store routes to QMD). Everything else is allowed.
  def classify(path, plastic_home:)
    return :allow if path.nil? || path.empty?
    store_path?(path, plastic_home: plastic_home) ? :qmd : :allow
  end

  # A path AT or UNDER the global store or a project store. We gate the whole store
  # tree (not just `*.md`) because a content search root is usually a directory:
  # grepping the store scans its markdown, which is exactly what QMD should serve.
  def store_path?(path, plastic_home:)
    abs = absolutize(path)
    home = File.expand_path(plastic_home)
    global = File.join(home, "store")
    return true if abs == global || abs.start_with?("#{global}/")

    projects = File.join(home, "projects")
    return false unless abs.start_with?("#{projects}/")
    tail = abs[(projects.length + 1)..].to_s.split(File::SEPARATOR)
    tail.length >= 2 && tail[1] == "store"
  end

  def absolutize(path)
    File.absolute_path?(path) ? path : File.expand_path(path)
  end

  # --- bypass ---

  # Only Bash commands carry a trailing `# qmd-ok` comment. The token must be a real
  # trailing comment (BYPASS_RE), so a quoted/echoed occurrence does not bypass.
  def bypass?(tool_name, tool_input)
    return false unless tool_name.to_s == "Bash"
    cmd = tool_input.is_a?(Hash) ? tool_input["command"].to_s : ""
    BYPASS_RE.match?(cmd.chomp)
  end

  # --- target extraction ---

  # Paths a CONTENT-SEARCH operation scans. Reads (Read, cat/head/tail) and
  # structural discovery (Glob, find, ls) are NOT content search -> no targets ->
  # always allowed. Only the Grep tool and bash grep/rg/ag can be gated. Read
  # vectors only (this is a READ gate); write vectors are bridge.rb's job.
  def extract_targets(tool_name, tool_input, cwd:)
    input = tool_input.is_a?(Hash) ? tool_input : {}
    case tool_name.to_s
    when "Grep"
      # The search root is the target; the query text is not a path.
      [input["path"]].compact.reject { |s| s.to_s.empty? }
    when "Bash"
      bash_search_targets(input["command"].to_s)
    else
      # Read, Glob, and every other tool: read / structural op -> never gated.
      []
    end
  end

  # CONTENT-SEARCH path args across a compound command. Conservative: missing an
  # exotic form is fine; never flag /dev/null or pure pipes.
  def bash_search_targets(command)
    return [] unless command.is_a?(String) && !command.empty?
    targets = []
    command.split(/[;\n]|&&|\|\||\|/).each do |segment|
      targets.concat(segment_search_targets(segment))
    end
    targets.reject { |t| t.nil? || t.empty? || dev_path?(t) }.uniq
  end

  def segment_search_targets(segment)
    tokens = tokenize(segment)
    return [] if tokens.empty?

    # Skip leading env-style assignments (FOO=bar cmd ...).
    idx = 0
    idx += 1 while tokens[idx] && tokens[idx].include?("=") && tokens[idx] !~ /\A-/
    util = File.basename(tokens[idx].to_s)
    return [] unless CONTENT_SEARCH_UTILS.include?(util)

    args = tokens[(idx + 1)..] || []
    path_args_for(args)
  end

  # Collect path-shaped arguments for a content-search util. Flags are skipped; the
  # first non-flag bareword is the PATTERN, not a path.
  def path_args_for(args)
    paths = []
    pattern_consumed = false
    args.each do |a|
      next if a.start_with?("-")
      unless pattern_consumed
        pattern_consumed = true
        next
      end
      paths << a
    end
    paths
  end

  # Minimal tokenizer: split on whitespace, strip surrounding matching quotes off
  # each token. Good enough for the conservative read-vector parse.
  def tokenize(segment)
    segment.to_s.strip.split(/\s+/).map { |t| strip_quotes(t) }
  end

  def strip_quotes(token)
    if (token.start_with?('"') && token.end_with?('"')) ||
       (token.start_with?("'") && token.end_with?("'"))
      token[1..-2].to_s
    else
      token
    end
  end

  def dev_path?(path)
    path == "/dev/null" || path.start_with?("/dev/")
  end

  # --- reasons ---

  def qmd_reason(path)
    "retrieval gate: search the store via QMD, not a raw content scan. Reading a " \
      "known file and listing/globbing the store are fine; only CONTENT SEARCH over " \
      "store markdown routes through QMD. Use `qmd search`/`qmd query` over the " \
      "`plastic-*` collections (or `scripts/qmd-sync search`) instead of scanning " \
      "#{path}. If QMD's results do not answer your need (your reading of the " \
      "snippets, not their score), append a trailing `# qmd-ok` to a Bash command."
  end
end
