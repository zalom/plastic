# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "time"

require_relative "../scripts/lib/runner_policy"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/agent_models"

# RunnerPolicy (intent 340, G7, n5): the kind table. Matrix rows 5.12-5.17
# and 5.21 in actions/ACTION_1.md n5 (every other n5 row lives in
# runner_dispatch_test.rb).
class RunnerPolicyTest < Minitest::Test
  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def entries_for(content)
    NodeLedger.entries_from_content(content)
  end

  # --- 5.12: the soft cap counts failed_verification lines, never attempts -------

  def test_retry_cap_counts_failed_verification_only
    reclaims_only = entries_for(
      line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1", model: "sonnet") +
      line("n1", "reclaimed", holder: "h", expired: "2026-01-01T01:00:00Z") +
      line("n1", "running", holder: "h", expires: "2026-01-01T02:00:00Z", packet: "p2", model: "sonnet") +
      line("n1", "reclaimed", holder: "h", expired: "2026-01-01T02:00:00Z")
    )
    assert_equal 0, RunnerPolicy.retry_count(reclaims_only, "n1"),
                 "a reclaimed crash must never count as a failure"
    refute RunnerPolicy.at_retry_cap?(reclaims_only, "n1", "work")

    with_failures = entries_for(
      line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p1", model: "sonnet") +
      line("n1", "failed_verification", holder: "h", gates: "g", reason: "suite_red") +
      line("n1", "running", holder: "h", expires: "2026-01-01T02:00:00Z", packet: "p2", model: "sonnet") +
      line("n1", "failed_verification", holder: "h", gates: "g", reason: "suite_red")
    )
    assert_equal 2, RunnerPolicy.retry_count(with_failures, "n1")
    assert RunnerPolicy.at_retry_cap?(with_failures, "n1", "work")
  end

  # --- 5.13: work and research resolve the executor model, config override works -

  def test_work_and_research_use_executor_model
    default_model = RunnerPolicy.model_for("work", config: {})
    assert_equal default_model, RunnerPolicy.model_for("research", config: {})

    config = { "agents" => { "models" => { "claude" => { "plastic-executor" => "haiku" } } } }
    assert_equal "haiku", RunnerPolicy.model_for("work", config: config)
    assert_equal "haiku", RunnerPolicy.model_for("research", config: config)
  end

  # --- 5.14: verify resolves the advisor model, never the cheap tier -------------

  def test_verify_uses_advisor_model
    assert_equal RunnerPolicy::DEFAULT_ADVISOR_MODEL, RunnerPolicy.model_for("verify", config: {})
    refute_equal RunnerPolicy::DEFAULT_EXECUTOR_MODEL, RunnerPolicy.model_for("verify", config: {})

    config = { "agents" => { "models" => { "plastic-advisor" => "fable" } } }
    assert_equal "fable", RunnerPolicy.model_for("verify", config: config)
    # a config override for the executor role must never leak into the advisor role
    exec_only = { "agents" => { "models" => { "claude" => { "plastic-executor" => "haiku" } } } }
    assert_equal RunnerPolicy::DEFAULT_ADVISOR_MODEL, RunnerPolicy.model_for("verify", config: exec_only)
  end

  # --- 5.15: a blank config falls back to a shipped default, never "" -----------

  def test_model_falls_back_to_shipped_default
    assert_equal RunnerPolicy::DEFAULT_EXECUTOR_MODEL, RunnerPolicy.model_for("work", config: {})
    assert_equal RunnerPolicy::DEFAULT_ADVISOR_MODEL, RunnerPolicy.model_for("verify", config: {})
    refute_empty RunnerPolicy.model_for("work", config: nil)

    blank_config = { "agents" => { "models" => { "claude" => { "plastic-executor" => "  " } } } }
    assert_equal RunnerPolicy::DEFAULT_EXECUTOR_MODEL, RunnerPolicy.model_for("work", config: blank_config)
  end

  # --- 5.16: only work gets a worktree -------------------------------------------

  def test_worktree_only_for_work_kind
    assert RunnerPolicy.worktree?("work")
    refute RunnerPolicy.worktree?("verify")
    refute RunnerPolicy.worktree?("research")
    refute RunnerPolicy.worktree?("decision")
  end

  # --- 5.17: an unknown kind gets work's whole row, never no policy -------------

  def test_unknown_kind_uses_work_policy
    assert_equal RunnerPolicy.retry_cap("work"), RunnerPolicy.retry_cap("bogus")
    assert_equal RunnerPolicy.retry_cap("work"), RunnerPolicy.retry_cap(nil)
    assert_equal RunnerPolicy.model_for("work"), RunnerPolicy.model_for("bogus")
    assert_equal RunnerPolicy.worktree?("work"), RunnerPolicy.worktree?("bogus")
    assert_equal RunnerPolicy.lease_minutes("work"), RunnerPolicy.lease_minutes("bogus")
  end

  # --- 5.21: expires= is a function of the kind's own lease length ---------------

  def test_lease_length_comes_from_kind
    now = Time.utc(2026, 1, 1, 0, 0, 0)
    work_expires = Time.iso8601(RunnerPolicy.lease_expires("work", now: now))
    verify_expires = Time.iso8601(RunnerPolicy.lease_expires("verify", now: now))
    research_expires = Time.iso8601(RunnerPolicy.lease_expires("research", now: now))

    refute_equal work_expires, verify_expires
    refute_equal work_expires, research_expires
    assert_operator work_expires, :>, verify_expires,
                     "a long work build must not share verify's short lease"
    assert_operator work_expires, :>, now
  end

  # --- 10.19: the shipped executor default resolves through AgentModels ------
  #
  # A value comparison cannot tell "hardcoded, coincidentally equal" apart
  # from "resolved through AgentModels::TIER_DEFAULTS" (both read "sonnet"
  # today, and Ruby's frozen-string-literal dedup even makes them the same
  # object). This reads RunnerPolicy's OWN declaration line and requires it
  # to name AgentModels::TIER_DEFAULTS, never a second bare literal.

  def test_models_resolve_through_agent_models
    assert_equal "sonnet", AgentModels::TIER_DEFAULTS.fetch("plastic-executor"),
                 "fixture assumption: this test targets the shipped plastic-executor tier"

    source = File.read(File.expand_path("../scripts/lib/runner_policy.rb", __dir__))
    default_line = source[/^\s*DEFAULT_EXECUTOR_MODEL\s*=.*$/]
    refute_nil default_line, "DEFAULT_EXECUTOR_MODEL must be declared in runner_policy.rb"
    assert_match(/AgentModels::TIER_DEFAULTS/, default_line,
                 "RunnerPolicy's default executor model must be resolved through " \
                 "AgentModels::TIER_DEFAULTS, not a second hardcoded literal (D19)")
    refute_match(/"sonnet"/, default_line,
                 "must resolve through AgentModels::TIER_DEFAULTS alone, not also carry the bare literal")
    assert_equal AgentModels::TIER_DEFAULTS.fetch("plastic-executor"), RunnerPolicy::DEFAULT_EXECUTOR_MODEL
  end
end
