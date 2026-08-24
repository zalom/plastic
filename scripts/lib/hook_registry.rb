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

  # Per-gate tool applicability for the merged CODEX edit-path dispatcher (intent
  # 251, spec D1). Codex reports exactly one file-mutation tool name, apply_patch
  # (intent 181 F4), so every value is the same single-entry list. The table is
  # NOT decoration: EditGates.tool_applies? builds a regex from these values, and
  # reusing GATE_TOOLS here would match none of them against "apply_patch" and
  # silently skip all five gates. Key order IS the evaluation order and is the
  # SAME order GATE_TOOLS uses (spec D5), so the two harnesses evaluate the five
  # gates in one order, not two.
  CODEX_GATE_TOOLS = {
    "savepoint-pre" => %w[apply_patch].freeze,
    "lock-gate"     => %w[apply_patch].freeze,
    "code-gate"     => %w[apply_patch].freeze,
    "links-gate"    => %w[apply_patch].freeze,
    "create-gate"   => %w[apply_patch].freeze,
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
  #
  # Codex's apply_patch matcher carries ONE dispatcher command, edit-gates,
  # which runs all five gates in-process through scripts/lib/codex_edit_gates.rb
  # (intent 251), mirroring what intent 244 did for Claude. Five separately
  # registered commands used to cost eight OS processes per edit (five
  # top-level plus three nested run_core children); one dispatcher process
  # reaches the same five gate decisions.
  CODEX_PRE_HOOKS  = %w[edit-gates].freeze
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
    # Every Codex hook name is now a name `events` itself carries (intent 251,
    # spec D9): edit-gates is Claude's own PreToolUse hook name, so there is
    # nothing left to merge in from a separate status table.
    status_by_name = events.values.flatten.flat_map { |g| g["hooks"] }
                           .each_with_object({}) { |h, m| m[h["name"]] = h["status"] }
    cmd = ->(name) {
      { "type" => "command",
        "command" => "\"#{dispatcher_path}\" #{name}",
        "statusMessage" => status_by_name[name].to_s }
    }
    # Preserve the order these hook names appear across the PreToolUse groups in `events`.
    pre_order = events["PreToolUse"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    # The Codex apply_patch matcher carries the same edit-gates name Claude's own
    # PreToolUse group carries (intent 251, spec D9), so the intersection with
    # pre_order validates the Codex gate name against the single source of truth,
    # `events`, rather than against a table of Claude tool applicability.
    pre = (CODEX_PRE_HOOKS & pre_order).map { |n| cmd.call(n) }
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

  # Launchers the installer places in the agent's hooks dir that `events` does not
  # register (intent 204): plastic-statusline is the settings["statusLine"] command.
  # Defined here rather than in doctor_core so the installer's purge can recognise it
  # without depending on the doctor; Doctor::CLAUDE_NON_HOOK_LAUNCHERS aliases it.
  CLAUDE_NON_HOOK_LAUNCHERS = %w[plastic-statusline].freeze

  # Hook names Plastic HAS registered and no longer does (intent 275). Purge-only:
  # an old install still carries these entries in settings.json / hooks.json, and
  # nothing else can tell us they were ever ours.
  #
  # MAINTENANCE DUTY: renaming or removing a hook from `events` means adding its old
  # name here in the SAME change. Skip it and every existing install keeps a dead
  # registration no update will ever clean up.
  #
  # Never fold these into claude_launcher_names: that method is what doctor's
  # hooks_exist demands be present on disk, so a retired name there makes a correct
  # install report missing launchers.
  RETIRED_HOOK_NAMES = %w[
    code-gate create-gate links-gate lock-gate savepoint-pre
    qmd-search retrieval-gate model-instructions opus-manual
  ].freeze

  RETIRED_CLAUDE_LAUNCHERS = RETIRED_HOOK_NAMES.map { |n| "plastic-#{n}" }.freeze

  # Filenames of Plastic's Codex dispatcher, current and retired. Codex hooks are
  # not per-hook launcher files: every command is `"<dispatcher>" <name>`, so the
  # dispatcher's own filename is what identifies an entry as ours.
  CODEX_DISPATCHER_BASENAMES = %w[codex-hook].freeze

  # Every launcher name the installer may purge from settings.json: what we register
  # now, the non-hook launchers we place, and what we used to register.
  def claude_purgeable_launcher_names
    (claude_launcher_names + CLAUDE_NON_HOOK_LAUNCHERS + RETIRED_CLAUDE_LAUNCHERS).uniq.sort
  end

  # Current Codex hook names, from the same sources codex_hooks_json builds from.
  def codex_hook_names
    live = CODEX_LIVE_STATE_EVENTS.flat_map do |event|
      events[event].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    end
    (CODEX_PRE_HOOKS + CODEX_POST_HOOKS + CODEX_BASH_HOOKS + live).uniq.sort
  end

  def codex_purgeable_hook_names
    (codex_hook_names + RETIRED_HOOK_NAMES).uniq.sort
  end

  # Is this settings.json hook command one of OURS? (intent 275)
  #
  # Ownership is registry membership, never a substring: the substring test this
  # replaced deleted a user's own ~/.claude/hooks/plastic-writing-style hook on
  # update. Tokenised rather than first-token-only because legacy entries take the
  # form `ruby <path>/plastic-<name>.rb`, and those must still be purged.
  def claude_purge_command?(cmd)
    known = claude_purgeable_launcher_names
    command_basenames(cmd).any? { |name| known.include?(name) }
  end

  # Is this ~/.codex/hooks.json command one of ours? Every Plastic Codex entry
  # invokes our dispatcher by path (`"<plastic_home>/scripts/codex-hook" <name>`),
  # so the dispatcher's filename identifies it. Basename EQUALITY, so a user's
  # ~/bin/codex-hook-wrapper is not ours; the argument is not filtered on, because
  # a command that already runs our dispatcher is ours whatever gate it names, and
  # filtering would strand any name we forgot to retire.
  def codex_purge_command?(cmd)
    first = cmd.to_s.split(/\s+/).reject(&:empty?).first
    return false unless first

    CODEX_DISPATCHER_BASENAMES.include?(File.basename(first.delete("\"'")))
  end

  # Each whitespace-separated token reduced to a comparable launcher name:
  # quotes stripped, directories dropped, a trailing .rb removed.
  def command_basenames(cmd)
    cmd.to_s.split(/\s+/).reject(&:empty?).map do |token|
      File.basename(token.delete("\"'")).sub(/\.rb\z/, "")
    end
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
