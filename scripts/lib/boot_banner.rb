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
  def render(health:, version:)
    return "Plastic Core: health check error — run /plastic-doctor" if health.nil?

    if health[:status] == "pass"
      "Plastic Core loaded — v#{version || "unknown"}"
    else
      bad = first_problem(health[:checks])
      if bad
        "Plastic Core loaded with issues — #{bad[:name]}: #{bad[:message]} — run /plastic-doctor"
      else
        "Plastic Core loaded with issues — run /plastic-doctor"
      end
    end
  end

  # First failing check, else first warning, else nil.
  def first_problem(checks)
    checks = checks || []
    checks.find { |c| c[:status] == "fail" } || checks.find { |c| c[:status] == "warn" }
  end
end
