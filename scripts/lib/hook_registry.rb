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
        ] },
      ],
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
