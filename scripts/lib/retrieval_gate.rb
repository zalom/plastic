# encoding: UTF-8
# frozen_string_literal: true

require_relative "bridge"

# RetrievalGate — the single, pure decision for Lever 2 of intent 84.
#
# Given an agent tool call (Bash/Read/Grep/Glob) and injected capability signals,
# it decides whether to BLOCK the call (returning a redirect-to-QMD/Serena reason
# String) or ALLOW it (returning nil). All capability and freshness signals are
# injected by the caller (the hook); this module shells out to nothing, reads no
# globals, and runs no binaries. Mirrors bridge.rb's decision-fn convention
# (reason String to block, nil to allow).
#
# Classification (per target path):
#   - store `*.md` (under <plastic_home>/store or .../projects/<slug>/store) -> QMD
#   - Serena-supported code/data file (NOT a store markdown) -> SERENA
#   - images / binary / other -> ALLOWED
#
# Capability enforcement is BINARY (no advisory tier):
#   - QMD class: detected+fresh -> BLOCK; detected+stale -> fire reindex, ALLOW
#     this turn; absent/down -> ALLOW (no warning).
#   - SERENA class: detected -> BLOCK; absent -> ALLOW.
#
# Bypass: a TRAILING `# qmd-ok` shell comment on a Bash command (not a substring;
# a quoted/echoed occurrence does not bypass).
#
# Scope: only the agent's own tool calls. Ruby `File.read` inside scripts is
# invisible to a PreToolUse hook and is explicitly out of scope (no exemptions).
module RetrievalGate
  module_function

  # Serena LSP covers many languages incl. JSON/YAML/TOML/Markdown/Ruby. Keep a
  # small, conservative allowlist of code/data extensions. Markdown is listed but
  # store markdown is reclassified to QMD before Serena ever sees it.
  SERENA_EXTENSIONS = %w[
    rb js jsx ts tsx mjs cjs py go rs java kt scala c h cpp hpp cc
    cs php rb swift sh bash zsh lua ex exs erl clj sql
    json yaml yml toml md markdown
  ].freeze

  # Image / binary extensions that are always allowed (plain read is fine).
  BINARY_EXTENSIONS = %w[
    png jpg jpeg gif webp svg ico bmp tiff pdf
    zip gz tar tgz bz2 xz 7z
    mp3 mp4 mov avi wav flac ogg
    woff woff2 ttf otf eot
    bin exe dll so dylib o a class jar wasm
  ].freeze

  # A `# qmd-ok` token that is a real TRAILING shell comment, after stripping a
  # trailing newline. The token must be preceded by whitespace (or start the
  # command) and run to end-of-string. `echo "# qmd-ok"` does NOT match: the
  # token there is followed by a closing quote, not end-of-string.
  BYPASS_RE = /(?:\A|\s)#\s*qmd-ok\s*\z/.freeze

  # Decide. Returns nil to ALLOW, or a reason String to BLOCK.
  #   capabilities: { qmd:, qmd_fresh:, serena: } (booleans).
  #   reindex: no-arg callable fired once when a QMD-class target is STALE.
  # When bypassed, returns nil and (if given) yields :bypass to the optional
  # block so the caller can log it.
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
      case classify(path, plastic_home: plastic_home)
      when :qmd
        if capabilities[:qmd] && capabilities[:qmd_fresh]
          return qmd_reason(path)
        elsif capabilities[:qmd] # present but stale
          stale_seen = true
        end
        # absent/down -> allow this target
      when :serena
        return serena_reason(path) if capabilities[:serena]
      end
    end

    reindex.call if stale_seen
    nil
  end

  # --- classification ---

  def classify(path, plastic_home:)
    return :allow if path.nil? || path.empty?
    ext = extension(path)

    if store_markdown?(path, plastic_home: plastic_home)
      return :qmd
    end
    return :allow if BINARY_EXTENSIONS.include?(ext)
    return :serena if SERENA_EXTENSIONS.include?(ext)

    :allow
  end

  # A markdown file under the global store or a project store. QMD owns store
  # markdown even though Serena could also read markdown (QMD wins for the store).
  def store_markdown?(path, plastic_home:)
    return false unless %w[md markdown].include?(extension(path))
    abs = absolutize(path)
    home = File.expand_path(plastic_home)
    global = File.join(home, "store")
    return true if abs.start_with?("#{global}/")

    projects = File.join(home, "projects")
    return false unless abs.start_with?("#{projects}/")
    tail = abs[(projects.length + 1)..].to_s.split(File::SEPARATOR)
    tail.length >= 2 && tail[1] == "store"
  end

  def extension(path)
    File.extname(path.to_s).sub(/\A\./, "").downcase
  end

  def absolutize(path)
    File.absolute_path?(path) ? path : File.expand_path(path)
  end

  # --- bypass ---

  # Only Bash commands carry a trailing `# qmd-ok` comment. The token must be a
  # real trailing comment (BYPASS_RE), so a quoted/echoed occurrence does not
  # bypass.
  def bypass?(tool_name, tool_input)
    return false unless tool_name.to_s == "Bash"
    cmd = tool_input.is_a?(Hash) ? tool_input["command"].to_s : ""
    BYPASS_RE.match?(cmd.chomp)
  end

  # --- target extraction ---

  # Paths the call reads/scans. Conservative: missing an exotic form is fine;
  # never flag /dev/null or pure pipes. Read vectors only (this is a READ gate),
  # not the write vectors bridge.rb already covers.
  def extract_targets(tool_name, tool_input, cwd:)
    input = tool_input.is_a?(Hash) ? tool_input : {}
    case tool_name.to_s
    when "Read"
      [input["file_path"]].compact.reject(&:empty?)
    when "Glob"
      [input["path"], input["pattern"]].compact.reject { |s| s.to_s.empty? }
    when "Grep"
      # The search root is the target; the query text is not a path.
      [input["path"]].compact.reject { |s| s.to_s.empty? }
    when "Bash"
      bash_read_targets(input["command"].to_s)
    else
      []
    end
  end

  # READ utilities that take file/dir path arguments. Conservative parse: split
  # on shell separators, identify the utility, collect its non-flag path args.
  READ_UTILS = %w[grep rg ag find cat head tail less more bat ls wc nl sort uniq].freeze

  def bash_read_targets(command)
    return [] unless command.is_a?(String) && !command.empty?
    targets = []
    command.split(/[;\n]|&&|\|\||\|/).each do |segment|
      targets.concat(segment_read_targets(segment))
    end
    targets.reject { |t| t.nil? || t.empty? || dev_path?(t) }.uniq
  end

  def segment_read_targets(segment)
    tokens = tokenize(segment)
    return [] if tokens.empty?

    # Skip leading env-style assignments (FOO=bar cmd ...).
    idx = 0
    idx += 1 while tokens[idx] && tokens[idx].include?("=") && tokens[idx] !~ /\A-/
    util = File.basename(tokens[idx].to_s)
    return [] unless READ_UTILS.include?(util)

    args = tokens[(idx + 1)..] || []
    path_args_for(util, args)
  end

  # Collect path-shaped arguments for a read utility. Flags and flag-values are
  # skipped; for grep/rg the first non-flag bareword is the PATTERN, not a path.
  def path_args_for(util, args)
    skip_pattern = %w[grep rg ag].include?(util)
    paths = []
    pattern_consumed = false
    args.each do |a|
      next if a.start_with?("-")
      if skip_pattern && !pattern_consumed
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
    "retrieval gate: search the store via QMD, not raw grep/Read. " \
      "Use `qmd search`/`qmd query` over the `plastic-*` collections (or " \
      "`scripts/qmd-sync search`) instead of reading #{path}. " \
      "If you genuinely need the raw read, append a trailing `# qmd-ok` to a Bash command."
  end

  def serena_reason(path)
    "retrieval gate: navigate code via Serena's symbolic tools (find_symbol / " \
      "get_symbols_overview / find_referencing_symbols), not raw grep/Read of #{path}."
  end
end
