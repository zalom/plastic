# encoding: UTF-8
# frozen_string_literal: true

# HookRegistry: THE single source of truth for Plastic's hook registration
# (intent 108, D7). Three consumers, none of which may hand-roll matchers:
#   - InstallerCore#merge_claude_hooks builds settings.json entries from it
#   - hooks/hooks.json (legacy plugin surface) is pinned to it by test
#   - doctor's hooks_match_registry check compares live settings against it
# Change registrations HERE and only here.
module HookRegistry
  module_function

  # MCP tools that MUTATE files. Every write/lock/create gate must match them,
  # or symbolic edits bypass the whole gate layer (the universal MCP-edit
  # bypass found in 108's gate inventory).
  SERENA_EDIT_TOOLS = %w[
    mcp__serena__replace_content
    mcp__serena__replace_symbol_body
    mcp__serena__insert_after_symbol
    mcp__serena__insert_before_symbol
    mcp__serena__safe_delete_symbol
    mcp__serena__rename_symbol
  ].freeze

  WRITE_MATCHER = (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).join("|")

  # Per-gate tool applicability for the merged edit-path dispatcher (intent 244,
  # spec D-d/D-l). Registration collapses to ONE PreToolUse hook on WRITE_MATCHER
  # (a strict superset of the three former matcher groups), and this table is what
  # keeps each gate's own coverage exactly what it was: scripts/hook-edit-gates
  # reads tool_name off the payload and skips any gate whose list excludes it.
  # Key order IS the evaluation order (spec D-a): savepoint-pre first because it
  # never denies and its ledger append must stay unconditional; lock-gate leads
  # the deniers because holding the delivery lock is the precondition the other
  # rules assume. A test pins this table against today's three matcher groups, so
  # no gate's coverage can widen or narrow silently.
  GATE_TOOLS = {
    "savepoint-pre" => %w[Write Edit].freeze,
    "lock-gate"     => (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).freeze,
    "code-gate"     => (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).freeze,
    "links-gate"    => %w[Write Edit].freeze,
    "create-gate"   => (%w[Write Edit] + SERENA_EDIT_TOOLS).freeze,
  }.freeze

  # Per-gate statusMessage, kept as its own source because these five names stop
  # appearing in `events` once registration collapses, while Codex still
  # registers all five per-gate entries and must keep emitting today's exact
  # statusMessage strings (intent 244, spec D-e). codex_hooks_json merges this
  # under the names it derives from `events`.
  GATE_STATUS = {
    "code-gate"     => "Checking lifecycle gate...",
    "lock-gate"     => "Checking lock gate...",
    "savepoint-pre" => "Recording stage start...",
    "links-gate"    => "Checking Links gate...",
    "create-gate"   => "Checking create gate...",
  }.freeze

  # event => ordered list of { "matcher" =>, "hooks" => [{ "name" =>, "status" => }] }
  # The name is the hooks/<name> launcher; the flat install ships it as
  # ~/.claude/hooks/plastic-<name>.
  def events
    {
      "SessionStart" => [
        { "matcher" => "", "hooks" => [
          { "name" => "session-start", "status" => "Loading Plastic context..." },
          { "name" => "check-update", "status" => "" },
        ] },
      ],
      "PreCompact" => [
        { "matcher" => "", "hooks" => [
          { "name" => "savepoint", "status" => "Saving Plastic intent state..." },
        ] },
      ],
      "PreToolUse" => [
        # ONE registered edit-path hook (intent 244, spec D-d). WRITE_MATCHER is a
        # strict superset of the three matcher groups this replaces; per-gate tool
        # applicability lives in GATE_TOOLS above and is read by
        # scripts/hook-edit-gates, so no gate's coverage widened or narrowed.
        { "matcher" => WRITE_MATCHER, "hooks" => [
          { "name" => "edit-gates", "status" => "Checking Plastic gates..." },
        ] },
        { "matcher" => "Bash", "hooks" => [
          { "name" => "bash-gate", "status" => "Checking lifecycle gate..." },
        ] },
      ],
      "PostToolUse" => [
        { "matcher" => "Write|Edit", "hooks" => [
          { "name" => "gate-check", "status" => "Checking lifecycle gates..." },
        ] },
      ],
      "UserPromptSubmit" => [
        { "matcher" => "", "hooks" => [
          { "name" => "continue", "status" => "Checking for continue..." },
          { "name" => "future-intent-check", "status" => "Checking future intents..." },
          { "name" => "auto-arm", "status" => "Checking auto mode..." },
          { "name" => "power-tools", "status" => "Checking power tools..." },
        ] },
      ],
    }
  end

  # Codex registration (~/.codex/hooks.json, intent 102). Derived from `events`:
  # the file-mutation PreToolUse gate/savepoint hooks collapse from Claude's
  # multi-tool matchers onto Codex's single apply_patch tool (181 F4: apply_patch
  # is Codex's sole file-mutation tool; tool_name always reports apply_patch), plus
  # the PostToolUse gate-check. Command invokes the codex-hook dispatcher with the
  # gate name. Guide-settled shape [guide Part 3]: top-level {"hooks":{<Event>:
  # [{"matcher","hooks":[{"type":"command","command","statusMessage"}]}]}},
  # identical to Claude's shape, string command. Single source of truth (108 D7):
  # any drift from `events` is a bug, pinned by test.
  CODEX_PRE_HOOKS  = %w[code-gate lock-gate savepoint-pre links-gate create-gate].freeze
  CODEX_POST_HOOKS = %w[gate-check].freeze

  # Codex's shell-tool gate hole (intent 203): bash-gate (denies a shell write to
  # project code before How) belongs on the Bash matcher, and ONLY Bash: the
  # official Codex hooks doc's PreToolUse event catalog enumerates exactly Bash,
  # apply_patch, and MCP tool calls, and neither it nor the two prior Codex
  # research passes (198's official-docs research, 181's deep research)
  # documents a discrete Read, Grep, or Glob tool name (D3). Registering a tool
  # name Codex never reports would be dead weight that looks alive, the exact
  # defect this intent exists to fix.
  CODEX_BASH_HOOKS = %w[bash-gate].freeze

  # Live-state events registered WHOLE (intent 199), unlike CODEX_PRE_HOOKS/
  # CODEX_POST_HOOKS above: Codex's SessionStart/UserPromptSubmit/PreCompact already
  # match Claude's shape exactly, one matcher group each ("", no tool to collapse
  # onto), so every hook `events` lists under these three events projects straight
  # through with no allowlist to keep in sync. A hook added to any of them on the
  # Claude side registers for Codex automatically.
  CODEX_LIVE_STATE_EVENTS = %w[SessionStart UserPromptSubmit PreCompact].freeze

  def codex_hooks_json(dispatcher_path:)
    # GATE_STATUS first, then `events`, so `events` still wins for every name it
    # carries. The five edit-path gate names left `events` when Claude's
    # registration collapsed to one hook (intent 244), but Codex still registers
    # all five separately and must keep emitting today's exact statusMessage
    # strings; without this merge every Codex statusMessage would silently become
    # "" and doctor's command-only diff would never notice.
    status_by_name = GATE_STATUS.merge(
      events.values.flatten.flat_map { |g| g["hooks"] }
            .each_with_object({}) { |h, m| m[h["name"]] = h["status"] }
    )
    cmd = ->(name) {
      { "type" => "command",
        "command" => "\"#{dispatcher_path}\" #{name}",
        "statusMessage" => status_by_name[name].to_s }
    }
    # Preserve the order these hook names appear across the PreToolUse groups in `events`.
    pre_order = events["PreToolUse"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    # Claude's edit-path groups collapsed to one hook, so the per-gate order can no
    # longer be read out of `events` (spec D-l). CODEX_PRE_HOOKS is its own literal
    # order (code-gate lock-gate savepoint-pre links-gate create-gate) and the
    # intersection with GATE_TOOLS.keys still validates that every Codex gate name
    # exists in the registry. The emitted JSON is unchanged.
    pre = (CODEX_PRE_HOOKS & GATE_TOOLS.keys).map { |n| cmd.call(n) }
    bash = (pre_order & CODEX_BASH_HOOKS).map { |n| cmd.call(n) }
    post = CODEX_POST_HOOKS.map { |n| cmd.call(n) }

    result = {
      "PreToolUse"  => [
        { "matcher" => "apply_patch", "hooks" => pre },
        { "matcher" => "Bash", "hooks" => bash },
      ],
      "PostToolUse" => [{ "matcher" => "apply_patch", "hooks" => post }],
    }
    CODEX_LIVE_STATE_EVENTS.each do |event|
      names = events[event].flat_map { |g| g["hooks"].map { |h| h["name"] } }
      result[event] = [{ "matcher" => "", "hooks" => names.map { |n| cmd.call(n) } }]
    end
    result
  end

  # Flattened, deduplicated Claude launcher names for every hook `events`
  # registers (intent 204): each hook name maps to a hooks/<name> launcher
  # installed as ~/.claude/hooks/plastic-<name>. The single derivation doctor's
  # hooks_exist/hooks_executable/hooks_no_orphans checks read from, so a
  # hand-kept list of launchers can never drift out of step with `events`
  # again (the gap that let 8 of 15 launchers, all the enforcement gates, go
  # unchecked).
  def claude_launcher_names
    events.values.flatten.flat_map { |g| g["hooks"].map { |h| h["name"] } }
          .uniq.sort.map { |name| "plastic-#{name}" }
  end

  # The settings.json shape merge_claude_hooks expects: single-group events map
  # to a Hash, multi-group events to an Array (the merge loop handles both).
  def claude_settings_hooks(hook_dir:)
    events.each_with_object({}) do |(event, groups), out|
      mapped = groups.map do |g|
        {
          "matcher" => g["matcher"],
          "hooks" => g["hooks"].map do |h|
            { "type" => "command",
              "command" => File.join(hook_dir, "plastic-#{h['name']}"),
              "statusMessage" => h["status"] }
          end,
        }
      end
      out[event] = mapped.length == 1 ? mapped.first : mapped
    end
  end
end
