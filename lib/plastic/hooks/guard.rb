# frozen_string_literal: true

require "json"
require_relative "../cli/hook"
require_relative "guard_verdict"

module Plastic
  module Hooks
    # PreToolUse: refuses an agent write to a core file of a store, to any file of a closed intent, to a folder no
    # intent owns and to an intent record in the project tree, with the harness's deny decision and its reason. Any
    # other call, and any error, passes with no output.
    class Guard < CLI::Hook
      skips_daily_backup
      changes({})

      def respond(event)
        reason = GuardVerdict.new(home: scope.plastic_home, cwd: directory).reason(event[:tool_name].to_s, event[:tool_input])
        reason && JSON.generate({ "hookSpecificOutput" => { "hookEventName" => "PreToolUse", "permissionDecision" => "deny",
                                                            "permissionDecisionReason" => reason } })
      end
    end
  end
end
