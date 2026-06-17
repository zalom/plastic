# encoding: UTF-8
# frozen_string_literal: true

# Renders the SessionStart boot banner from a core-health result (intent 36a).
#
# Pure and dependency-injected: it takes the health hash (the return value of
# Doctor#run_core_checks) and the version string, and returns a single banner
# line. No I/O, no globals, no ENV — so it is unit-testable in isolation while
# the hook feeds it real data.
module BootBanner
  module_function

  # health: the Hash returned by Doctor#run_core_checks, or nil if the check
  #         itself raised (degraded to an error banner).
  # version: the installed Plastic version string, or nil.
  #
  # Returns one of two binary lines:
  #   "Plastic Core loaded — v{VER} | doctor --core run: success"
  #   "Plastic Core loaded — v{VER} | doctor --core run: error — run /plastic-doctor"
  def render(health:, version:)
    ver = version || "unknown"
    if !health.nil? && health[:status] == "pass"
      "Plastic Core loaded — v#{ver} | doctor --core run: success"
    else
      "Plastic Core loaded — v#{ver} | doctor --core run: error — run /plastic-doctor"
    end
  end
end
