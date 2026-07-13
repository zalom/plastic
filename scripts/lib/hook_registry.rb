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
  CREATE_MATCHER = (%w[Write Edit] + SERENA_EDIT_TOOLS).join("|")

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
        { "matcher" => WRITE_MATCHER, "hooks" => [
          { "name" => "code-gate", "status" => "Checking lifecycle gate..." },
          { "name" => "lock-gate", "status" => "Checking lock gate..." },
        ] },
        { "matcher" => "Write|Edit", "hooks" => [
          { "name" => "savepoint-pre", "status" => "Recording stage start..." },
        ] },
        { "matcher" => CREATE_MATCHER, "hooks" => [
          { "name" => "create-gate", "status" => "Checking create gate..." },
        ] },
        { "matcher" => "Bash", "hooks" => [
          { "name" => "bash-gate", "status" => "Checking lifecycle gate..." },
        ] },
        { "matcher" => "Bash|Read|Grep|Glob", "hooks" => [
          { "name" => "retrieval-gate", "status" => "Checking retrieval gate..." },
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
          { "name" => "qmd-search", "status" => "Searching QMD..." },
          { "name" => "opus-manual", "status" => "Checking Opus manual..." },
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
  CODEX_PRE_HOOKS  = %w[code-gate lock-gate savepoint-pre create-gate].freeze
  CODEX_POST_HOOKS = %w[gate-check].freeze

  def codex_hooks_json(dispatcher_path:)
    # name => statusMessage, straight from the single `events` source (A8): the
    # guide Part 3 hooks.json format carries a per-hook statusMessage, so emit it.
    status_by_name = events.values.flatten.flat_map { |g| g["hooks"] }
                           .each_with_object({}) { |h, m| m[h["name"]] = h["status"] }
    cmd = ->(name) {
      { "type" => "command",
        "command" => "\"#{dispatcher_path}\" #{name}",
        "statusMessage" => status_by_name[name].to_s }
    }
    # Preserve the order these hook names appear across the PreToolUse groups in `events`.
    pre_order = events["PreToolUse"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    pre = (pre_order & CODEX_PRE_HOOKS).map { |n| cmd.call(n) }
    post = CODEX_POST_HOOKS.map { |n| cmd.call(n) }
    {
      "PreToolUse"  => [{ "matcher" => "apply_patch", "hooks" => pre }],
      "PostToolUse" => [{ "matcher" => "apply_patch", "hooks" => post }],
    }
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
