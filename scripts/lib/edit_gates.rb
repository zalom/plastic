# encoding: UTF-8
# frozen_string_literal: true

# EditGates (intent 244): the five Claude PreToolUse edit-path gates as plain
# functions over one parsed payload. Two callers share these functions so the
# harnesses cannot drift: scripts/hook-edit-gates (the merged Claude dispatcher)
# and the retained scripts/hook-code-gate / hook-lock-gate / hook-savepoint-pre
# CLI wrappers that scripts/codex-hook still popens per file op.
#
# A gate returns nil to allow, or a Deny. Two deny shapes coexist deliberately
# (spec D-b): :stderr (stderr lines plus exit 2, code-gate / links-gate /
# create-gate) and :json (stdout JSON plus exit 0, lock-gate, which reserves a
# non-zero exit for hook-internal errors). Nothing here normalizes them.

require "json"
require "time"
require_relative "hook_registry"
require_relative "bridge"
require_relative "lock"
require_relative "links_gate"
require_relative "intent_validator"

module EditGates
  module_function

  ALLOW = nil

  Deny = Struct.new(:shape, :lines, :stdout, keyword_init: true)

  # Everything the five gates read out of one PreToolUse payload (spec D-g).
  #   gate_path  - code-gate and lock-gate: file_path || notebook_path ||
  #                relative_path, absolutized against tool_input.project_root ||
  #                payload.cwd when relative. Exactly what the old Bash shims
  #                computed with their `ruby -rjson -e` one-liners.
  #   file_path  - savepoint-pre, links-gate, create-gate: tool_input.file_path
  #                only, raw. Preserving this narrower extraction is what keeps
  #                create-gate's dormant Serena gap byte-for-byte intact.
  #   content    - the RAW tool_input.content (nil when the key is absent, ""
  #                when it is explicitly empty). Kept unmixed with new_string so
  #                links-gate and create-gate's `!content.nil?` branch keeps its
  #                exact original meaning; code-gate computes its own combined
  #                content-or-new_string-or-"" value locally, mirroring what its
  #                old Bash shim computed independently for ARGV[2].
  Context = Struct.new(:tool_name, :session, :gate_path, :file_path, :content,
                       :old_string, :new_string, :replace_all, :harness,
                       keyword_init: true) do
    # links-gate and create-gate branch on content.nil? (key absent) vs content
    # present (even ""). This is the raw field already, kept as a named reader
    # so both gates read intent, not a struct field, at the call site.
    def content_or_nil
      content
    end
  end

  def context_from(payload, env: ENV)
    input = payload["tool_input"] || payload["tool_params"] || {}
    input = {} unless input.is_a?(Hash)

    raw = input["file_path"] || input["notebook_path"] || input["relative_path"] || ""
    if !raw.empty? && !raw.start_with?("/")
      root = input["project_root"] || payload["cwd"] || ""
      raw = File.join(root, raw) unless root.empty?
    end

    session = payload["session_id"]
    session = env["CLAUDE_CODE_SESSION_ID"] if session.to_s.empty?

    Context.new(
      tool_name: payload["tool_name"],
      session: (session unless session.to_s.empty?),
      gate_path: raw,
      file_path: input["file_path"],
      content: input["content"],
      old_string: input["old_string"],
      new_string: input["new_string"],
      replace_all: input["replace_all"],
      harness: "claude",
    )
  end

  # --- savepoint-pre (intent 81): never denies; appends the `started` ledger line.
  def savepoint_pre(ctx)
    path = ctx.file_path
    return ALLOW if path.nil? || path.empty?

    abs = File.expand_path(path)
    intent_dir = Bridge.intent_dir_for(abs)
    return ALLOW unless intent_dir

    begin
      Bridge.append_started_savepoint(intent_dir, abs)
    rescue StandardError
      # best-effort; the ledger is rebuildable and the post line still lands
    end
    ALLOW
  end

  # --- lock-gate (intent 96, 111): fail-CLOSED delivery lock plus the artifact claim.
  def lock_gate(ctx)
    file_path = ctx.gate_path
    return ALLOW if file_path.nil? || file_path.empty?

    session = ctx.session
    harness = ctx.harness

    bridge_data = Bridge.discover_bridge(session: session, cwd: Dir.pwd)
    reason = Bridge.lock_gate_decision(bridge_data, file_path, session: session, harness: harness)

    unless reason
      begin
        dir = Bridge.intent_dir_for(file_path)
        Lock.heartbeat(dir, session: session) if dir && !session.to_s.empty?
      rescue StandardError
        # ignore
      end

      begin
        dir = Bridge.intent_dir_for(file_path)
        artifact = File.basename(file_path) if dir
        if dir && artifact
          claim_reason = Claim.claim_gate_reason(dir, artifact, session: session, harness: harness)
          return deny_json(claim_reason) if claim_reason

          if Claim.fail_open?(dir, artifact)
            $stderr.puts "plastic claim gate: unresolvable claim on #{artifact} in " \
                         "intent #{Bridge.intent_id_from_dir(dir)} yielded; write " \
                         "proceeds (see /plastic-lock status)"
          end

          Claim.heartbeat(dir, artifact, session: session) rescue nil
        end
      rescue StandardError
        # ignore: a claim-gate bug must never block a write (fail open)
      end

      return ALLOW
    end

    deny_json(reason)
  end

  def deny_json(reason)
    Deny.new(shape: :json, stdout: JSON.generate(
      "hookSpecificOutput" => {
        "hookEventName" => "PreToolUse",
        "permissionDecision" => "deny",
        "permissionDecisionReason" => reason,
      }
    ))
  end

  # --- code-gate (intents 27, 73c2, 150): stage rule OR worktree rule, first match wins.
  def code_gate(ctx)
    file_path = ctx.gate_path
    return ALLOW if file_path.nil? || file_path.empty?

    session = ctx.session
    # Auditable escape (intent 150): mirrors the old Bash shim's independent
    # ti["content"] || ti["new_string"] || "" computation for ARGV[2]. Kept
    # local to code-gate; links-gate and create-gate never read it.
    new_content = ctx.content || ctx.new_string || ""

    if new_content && Bridge::PLASTIC_OK_RE.match?(new_content.chomp)
      log_escape(session, file_path)
      return ALLOW
    end

    bridge_data = Bridge.discover_bridge(session: session, cwd: file_path, edited_path: file_path)
    return ALLOW unless bridge_data

    reason = Bridge.code_gate_decision(bridge_data, file_path) ||
             Bridge.worktree_gate_decision(bridge_data, file_path, current_session: session)
    return ALLOW unless reason

    Deny.new(shape: :stderr, lines: ["PLASTIC GATE — #{reason}"])
  end

  def log_escape(session, file_path)
    require "fileutils"
    log = File.join(Dir.home, ".plastic", ".cache", "gate-escapes.log")
    FileUtils.mkdir_p(File.dirname(log))
    File.open(log, "a") do |io|
      io.puts("#{Time.now.utc.iso8601}\t#{session}\t#{file_path}")
    end
  rescue StandardError
    # the escape still applies; logging is best-effort
  end

  # --- links-gate (intent 192): the write-time belt for the ## Links contract.
  def links_gate(ctx)
    path = ctx.file_path
    return ALLOW if path.to_s.strip.empty?

    abs = File.expand_path(path)
    return ALLOW unless LinksGate.intent_file?(abs)

    content = ctx.content_or_nil
    old_string = ctx.old_string

    before_content = File.exist?(abs) ? File.read(abs) : ""

    after_content =
      if !content.nil?
        content
      elsif !old_string.nil?
        return ALLOW unless before_content.include?(old_string)
        ctx.replace_all ? before_content.gsub(old_string, ctx.new_string.to_s)
                        : before_content.sub(old_string, ctx.new_string.to_s)
      else
        return ALLOW # pathless mutation (no visible proposal); cannot judge, allow
      end

    plastic_home = ENV.fetch("PLASTIC_HOME") { File.join(Dir.home, ".plastic") }

    reason = LinksGate.decision(file_path: abs, before_content: before_content,
                                 after_content: after_content, plastic_home: plastic_home)
    return ALLOW unless reason

    Deny.new(shape: :stderr, lines: [reason])
  end

  # --- create-gate (intents 60b, 108 D7): validate the PROPOSED intent file content.
  def create_gate(ctx)
    path = ctx.file_path
    return ALLOW if path.nil? || path.to_s.strip.empty?

    abs = File.expand_path(path)
    dir = File.dirname(abs)
    is_intent_file = dir.match?(%r{/store/[^/]+--[^/]+\z}) &&
                     File.basename(abs) == "#{File.basename(dir)}.md"
    return ALLOW unless is_intent_file

    content = ctx.content_or_nil
    old_string = ctx.old_string

    result =
      if !content.nil?
        IntentValidator.validate_content(content)
      elsif !old_string.nil?
        unless File.exist?(abs)
          return Deny.new(shape: :stderr, lines: [
            "PLASTIC CREATE GATE — #{File.basename(abs)} does not exist; " \
            "create intents via new-intent / plastic-intent-creating.",
          ])
        end
        current = File.read(abs)
        return ALLOW unless current.include?(old_string)
        simulated = ctx.replace_all ? current.gsub(old_string, ctx.new_string.to_s)
                                    : current.sub(old_string, ctx.new_string.to_s)
        IntentValidator.validate_content(simulated)
      else
        unless File.exist?(abs)
          return Deny.new(shape: :stderr, lines: [
            "PLASTIC CREATE GATE — #{File.basename(abs)}: cannot read proposed " \
            "content and no file exists; refusing to allow an unvalidated intent write.",
          ])
        end
        IntentValidator.validate_content(File.read(abs))
      end

    return ALLOW if result[:ok]

    lines = ["PLASTIC CREATE GATE — #{File.basename(abs)} is not a valid intent:"]
    result[:errors].each { |e| lines << "  #{e}" }
    lines << "Create intents via new-intent / plastic-intent-creating; do not hand-author them."
    Deny.new(shape: :stderr, lines: lines)
  end

  # --- the ordered evaluation (spec D-a, D-i) -------------------------------
  # `route` is injected so a test can supply a raising gate and prove isolation
  # without eval, an ENV seam, or a global. `gate_tools` is injected for the same
  # reason and defaults to the single source of truth.
  # Returns the process exit code.
  def dispatch(ctx:, route:, gate_tools: HookRegistry::GATE_TOOLS, out: $stdout, err: $stderr)
    gate_tools.each do |gate, tools|
      next unless tools.include?(ctx.tool_name)

      outcome =
        begin
          route.call(gate, ctx)
        rescue StandardError => e
          err.puts "plastic #{gate} error: #{e.message}"
          next
        end

      next unless outcome

      if outcome.shape == :json
        out.print outcome.stdout
        return 0
      else
        outcome.lines.each { |line| err.puts line }
        return 2
      end
    end
    0
  end
end
