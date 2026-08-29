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

  # MCP tools that MUTATE files. The record hook must match them, or a symbolic
  # edit never reaches the savepoint ledger or the day ledger.
  SERENA_EDIT_TOOLS = %w[
    mcp__serena__replace_content
    mcp__serena__replace_symbol_body
    mcp__serena__insert_after_symbol
    mcp__serena__insert_before_symbol
    mcp__serena__safe_delete_symbol
    mcp__serena__rename_symbol
  ].freeze

  WRITE_MATCHER = (%w[Write Edit NotebookEdit] + SERENA_EDIT_TOOLS).join("|")

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
      "PostToolUse" => [
        { "matcher" => WRITE_MATCHER, "hooks" => [
          { "name" => "record", "status" => "Recording Plastic session state..." },
        ] },
      ],
      "SessionEnd" => [
        { "matcher" => "", "hooks" => [
          { "name" => "close", "status" => "Closing the Plastic session..." },
        ] },
      ],
      "UserPromptSubmit" => [
        { "matcher" => "", "hooks" => [
          { "name" => "capture", "status" => "Capturing prompt into the session ledger..." },
          { "name" => "power-tools", "status" => "Checking power tools..." },
        ] },
      ],
    }
  end

  # Codex registration (~/.codex/hooks.json, intent 102). Derived from `events`:
  # the PostToolUse record hook collapses from Claude's multi-tool matcher onto
  # Codex's single apply_patch tool (181 F4: apply_patch is Codex's sole
  # file-mutation tool; tool_name always reports apply_patch), and the live-state
  # events project through whole. Since intent 302 there is no PreToolUse group at
  # all: the edit-path gates are gone on both harnesses. Command invokes the
  # codex-hook dispatcher with the hook name. Guide-settled shape [guide Part 3]:
  # top-level {"hooks":{<Event>: [{"matcher","hooks":[{"type":"command","command",
  # "statusMessage"}]}]}}, identical to Claude's shape, string command. Single
  # source of truth (108 D7): any drift from `events` is a bug, pinned by test.
  CODEX_POST_HOOKS = %w[record].freeze

  # Live-state events registered WHOLE (intent 199): Codex's SessionStart/
  # UserPromptSubmit/PreCompact already match Claude's shape exactly, one matcher
  # group each ("", no tool to collapse onto), so every hook `events` lists under
  # these three events projects straight through with no allowlist to keep in
  # sync. A hook added to any of them on the Claude side registers for Codex
  # automatically.
  CODEX_LIVE_STATE_EVENTS = %w[SessionStart UserPromptSubmit PreCompact].freeze

  def codex_hooks_json(dispatcher_path:)
    status_by_name = events.values.flatten.flat_map { |g| g["hooks"] }
                           .each_with_object({}) { |h, m| m[h["name"]] = h["status"] }
    cmd = ->(name) {
      { "type" => "command",
        "command" => "\"#{dispatcher_path}\" #{name}",
        "statusMessage" => status_by_name[name].to_s }
    }
    # Validate the Codex name against the single source of truth, `events`.
    post_order = events["PostToolUse"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    post = (CODEX_POST_HOOKS & post_order).map { |n| cmd.call(n) }

    result = {
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
  # again (the gap that once let 8 of 15 launchers go unchecked).
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
    edit-gates bash-gate code-gate create-gate links-gate lock-gate savepoint-pre
    qmd-search retrieval-gate model-instructions opus-manual
    continue future-intent-check auto-arm gate-check
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
    (CODEX_POST_HOOKS + live).uniq.sort
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

  # Is this settings.json hook command one Plastic registers TODAY? (intent 277)
  #
  # The narrower twin of claude_purge_command?. The purge asks "was this ever
  # ours", because it has to recognise an old entry in order to remove it. A
  # liveness check asks "is there something here that still runs", and the two
  # sets differ by exactly the entries that make the answers disagree: a
  # SessionStart carrying only plastic-lock-gate satisfied doctor's
  # hooks_registered while no such launcher ships anymore.
  #
  # Sourced from claude_launcher_names alone, so RETIRED_CLAUDE_LAUNCHERS is out
  # (that is the bug) and CLAUDE_NON_HOOK_LAUNCHERS is out too: plastic-statusline
  # is settings["statusLine"], not a hook of any event, so a group whose only
  # Plastic entry is the statusline command has no hook registered in it.
  # Tokenised through command_basenames like the purge predicate, so a quoted
  # path or the legacy `ruby <path>/plastic-<name>.rb` form still resolves.
  def claude_current_command?(cmd)
    known = claude_launcher_names
    command_basenames(cmd).any? { |name| known.include?(name) }
  end

  # Is this ~/.codex/hooks.json command one of ours? Every Plastic Codex entry
  # invokes our dispatcher by path (`"<plastic_home>/scripts/codex-hook" <name>`),
  # so the dispatcher's filename identifies it. Basename EQUALITY, so a user's
  # ~/bin/codex-hook-wrapper is not ours; the argument is not filtered on, because
  # a command that already runs our dispatcher is ours whatever gate it names, and
  # filtering would strand any name we forgot to retire.
  #
  # Tokenised the same way claude_purge_command? is (command_basenames), NOT a
  # naive cmd.split.first: a first-token split breaks whenever plastic_home
  # contains a space, since the shell-quoted dispatcher path then splits across
  # multiple whitespace tokens and the true first token is only half the path.
  # command_basenames strips quote characters per token, so whichever token
  # carries the dispatcher's trailing `/codex-hook"` still resolves to the bare
  # basename "codex-hook" after its trailing quote is stripped.
  def codex_purge_command?(cmd)
    command_basenames(cmd).any? { |name| CODEX_DISPATCHER_BASENAMES.include?(name) }
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
