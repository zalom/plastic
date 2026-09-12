# encoding: UTF-8
# frozen_string_literal: true

require "json"
require_relative "active_delivery"
require_relative "lock"
require_relative "ready_set"

# StopGate (intent 340b, G7c, n4, D5/D7/D8/D9): may this session stop? Blocks
# only when four conditions hold together: the payload's stop_hook_active is
# true, runner.stop_hook parses as a real boolean true, this session holds
# the delivering intent's delivery.lock live and in auto mode, and the last
# runner step left work a new turn can actually move (some node is ready to
# dispatch right now - a graph whose only non-terminal node is already
# running, or that has no ready node at all, permits, because blocking that
# would trip Claude Code's own eight-block ceiling for nothing).
#
# Fail-open is the design, not a fallback: a missing store, a torn lock, an
# unreadable graph, a raised exception, a payload that is not JSON - every
# one of those permits. #decide never raises.
module StopGate
  module_function

  # decide(payload:, config_stop_hook:, session:, global_store:, project_roots:, ttl:, now:) ->
  # {block: false} or {block: true, reason: "..."}.
  #
  # `payload` is the hook input: already a Hash, or the raw JSON text (row
  # 4.19 - a payload that is not JSON permits, never raises). `config_stop_hook`
  # is the raw string read-config returns for runner.stop_hook: parsed as a
  # boolean here, never trusted as one.
  def decide(payload:, config_stop_hook:, session:, global_store:, project_roots:,
             ttl: Lock::TTL_SECONDS, now: Time.now, caps: nil)
    payload = parse_payload(payload)

    return permit unless payload["stop_hook_active"] == true
    return permit unless flag_true?(config_stop_hook)

    intent_dir = ActiveDelivery.resolve(global_store: global_store, project_roots: project_roots,
                                        session: session, ttl: ttl, now: now)
    return permit unless intent_dir

    lock = Lock.read(intent_dir)
    return permit unless lock
    return permit unless lock["run_mode"].to_s == "auto"

    return permit unless work_movable?(intent_dir, caps: caps)

    block(intent_dir)
  rescue StandardError
    permit
  end

  # Accepts a Hash as-is, parses a String as JSON, and falls back to an
  # empty Hash for anything else or anything that fails to parse - a
  # malformed payload must never raise (row 4.19).
  def parse_payload(payload)
    return payload if payload.is_a?(Hash)
    return {} unless payload.is_a?(String)

    parsed = JSON.parse(payload)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  # A config value counts as on only when it parses as the literal boolean
  # true (row 4.4): read-config emits strings, and the string "false" is
  # truthy in Ruby, so testing the raw value would arm the hook on its own
  # shipped default. Anything else, including an absent key (row 4.5), is off.
  def flag_true?(value)
    value.to_s.strip.downcase == "true"
  end

  # Some node is ready to dispatch right now. Never raises across this
  # boundary (ReadySet.analyze already never does); an unreadable or absent
  # graph, or an intent with no declared nodes, reads as ok: false or an
  # empty ready set either way, and both permit.
  def work_movable?(intent_dir, caps:)
    analysis = caps ? ReadySet.analyze(intent_dir, caps: caps) : ReadySet.analyze(intent_dir)
    analysis[:ok] && analysis[:ranked_ready].any?
  end

  def permit
    { block: false }
  end

  # Names the next instruction (row 4.17): a session that is blocked and
  # told nothing stops again immediately.
  def block(intent_dir)
    intent_id = File.basename(intent_dir.to_s)
    reason = "Plastic: intent #{intent_id} still has ready work. Run `runner step` for it " \
             "and dispatch what it prints before stopping."
    { block: true, reason: reason }
  end
end
