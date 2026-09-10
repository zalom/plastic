# encoding: UTF-8
# frozen_string_literal: true

require_relative "ready_set"
require_relative "node_worktree"
require_relative "agent_models"

# RunnerPolicy (intent 340, G7, n5): the kind table. Four facts per kind -
# which model it runs on, whether it gets a worktree, its SOFT retry cap, and
# its diff rule - looked up by one fallback rule: an unknown or nil kind gets
# `work`'s row, the widest of the four, never no policy at all (matrix 5.17,
# mirroring ReadySet's own `caps.fetch(kind) { caps["work"] }` fallback).
#
# This is deliberately a SECOND, SOFTER cap than ReadySet::DEFAULT_CAPS
# (327 D22): that cap is the transition layer's hard backstop, counted as
# `running` lines since the last terminal line, and `node-transition` is
# never changed to accept an override of it. RunnerPolicy's cap is counted
# from `failed_verification` lines alone (ReadySet.failed_verification_count,
# matrix 5.12) - a node reclaimed after a crash, with no failed_verification
# line at all, never trips this cap, exactly as 327 D12 specifies: "work runs
# ... retry cap 2 ... verify ... retry cap 1 ... research ... retry cap 1".
#
# Pure and dependency-injected: `model_for` takes `config:` (an already
# loaded config hash, AgentModels' own `agents.models` shape), never reads
# ENV or a real config.yml itself - the caller (RunnerDispatch) owns loading
# real config, this module only resolves values out of what it is handed.
module RunnerPolicy
  module_function

  # D31 (327): "One advisor: the smartest model available, or the model set
  # in user config." Never the cheap tier - that is the one thing D31 rules
  # out for a verify node (matrix 5.14).
  DEFAULT_EXECUTOR_MODEL = "sonnet"
  DEFAULT_ADVISOR_MODEL = "opus"

  EXECUTOR_CONFIG_KEY = "plastic-executor"
  ADVISOR_CONFIG_KEY = "plastic-advisor"

  # {model_role:, worktree:, retry_cap:, diff_rule:, lease_minutes:} per kind
  # (327 D12). `decision` carries no retry cap or lease: it is never
  # dispatched (RunnerDispatch stops the loop on one instead), so nothing
  # here ever needs to answer "how long is a decision node's lease".
  KIND_TABLE = {
    "work" => { model_role: :executor, worktree: true, retry_cap: 2, diff_rule: :inside_files,
                lease_minutes: 180 },
    "verify" => { model_role: :advisor, worktree: false, retry_cap: 1, diff_rule: :none,
                  lease_minutes: 30 },
    "research" => { model_role: :executor, worktree: false, retry_cap: 1, diff_rule: :none,
                    lease_minutes: 60 },
    "decision" => { model_role: nil, worktree: false, retry_cap: nil, diff_rule: :none,
                    lease_minutes: nil },
  }.freeze

  # matrix 5.17: an unknown, nil, or blank kind gets `work`'s whole row.
  def policy_for(kind)
    KIND_TABLE.fetch(kind.to_s, KIND_TABLE["work"])
  end

  # matrix 5.13/5.14/5.15: work and research resolve the executor model,
  # verify resolves the advisor model, and a config with no override falls
  # back to the shipped default rather than an empty string (`running`
  # requires a non-blank `model=`).
  def model_for(kind, config: {})
    policy_for(kind)[:model_role] == :advisor ? advisor_model(config: config) : executor_model(config: config)
  end

  def executor_model(config: {})
    resolve_model(config, EXECUTOR_CONFIG_KEY, DEFAULT_EXECUTOR_MODEL)
  end

  def advisor_model(config: {})
    resolve_model(config, ADVISOR_CONFIG_KEY, DEFAULT_ADVISOR_MODEL)
  end

  def resolve_model(config, key, shipped_default)
    value = AgentModels.models_section(config)[key]
    present?(value) ? value : shipped_default
  end
  private_class_method :resolve_model

  def present?(value)
    !(value.nil? || value.to_s.strip.empty?)
  end
  private_class_method :present?

  # matrix 5.16/5.17: only `work` gets a worktree; an unknown kind falls back
  # to `work`'s own row like every other field here. `KIND_TABLE["work"]` is
  # kept equal to `NodeWorktree::WORKTREE_KINDS` by the assertion below, so
  # the two lists cannot silently drift apart.
  raise "RunnerPolicy/NodeWorktree kind lists have drifted" unless KIND_TABLE.select { |_, v| v[:worktree] }.keys ==
                                                                    NodeWorktree::WORKTREE_KINDS

  def worktree?(kind)
    !!policy_for(kind)[:worktree]
  end

  def diff_rule(kind)
    policy_for(kind)[:diff_rule]
  end

  # matrix 5.12: the SOFT cap, or nil for a kind that carries none (decision).
  def retry_cap(kind)
    policy_for(kind)[:retry_cap]
  end

  # The soft-cap count itself: every non-torn `failed_verification` line for
  # `node`, delegated to ReadySet (matrix 5.12's "counts from
  # failed_verification lines", never from attempts).
  def retry_count(entries, node)
    ReadySet.failed_verification_count(entries, node.to_s)
  end

  # true only when a real cap exists AND the count has reached it (a nil cap,
  # e.g. `decision`, never trips).
  def at_retry_cap?(entries, node, kind)
    cap = retry_cap(kind)
    return false if cap.nil?

    retry_count(entries, node) >= cap
  end

  # matrix 5.21: `expires=` on `running` comes from the kind's own lease
  # length, never one shared constant - a long `work` build must not be
  # reclaimed under a still-working executor the way a quick `verify` pass
  # would be.
  def lease_minutes(kind)
    policy_for(kind)[:lease_minutes] || policy_for("work")[:lease_minutes]
  end

  def lease_expires(kind, now: Time.now)
    (now + (lease_minutes(kind) * 60)).utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end
end
