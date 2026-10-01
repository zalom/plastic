# encoding: UTF-8

require "json"

module SessionStartHook
  # Prints the hook's JSON payload, or exits silently when there is genuinely
  # nothing to surface (no active intent, no deprecations, no update notice).
  module Emit
    def self.call(parts, core_banner)
      return exit(0) if parts.join.strip.empty?

      payload = {
        "hookSpecificOutput" => {
          "hookEventName" => "SessionStart",
          "additionalContext" => parts.join("\n")
        },
        # Intent 54: additionalContext is model-only, so the banner stays invisible to
        # the human. The top-level systemMessage channel is rendered in the user's
        # terminal (and re-fires on /clear). Reuse the same BootBanner line so the
        # visible banner and the model-facing banner cannot drift.
        "systemMessage" => core_banner
      }
      puts JSON.generate(payload)
    end
  end
end
