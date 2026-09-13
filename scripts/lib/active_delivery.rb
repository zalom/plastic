# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require_relative "lock"

# ActiveDelivery (intent 340b, G7c, n4, D10): which intent a session is
# delivering. A lock is a file inside an intent directory, and intents live
# under the global store or under any configured project's store, so
# answering "which intent" needs a walk, not an index the way node_ids.rb
# indexes ids: one Dir.glob per configured root (plus one for the global
# store) and one JSON parse per candidate lock file. No validator, no graph
# rebuild, nothing else touches disk. Shared by StopGate (the fourth arming
# condition needs to know the lock's run_mode) and Handoff (the Runner
# section needs to know which intent's runner-step.last to render).
#
# Pure and dependency-injected: every call takes explicit paths; nothing
# here reads ENV, shells out, or raises across its own boundary.
module ActiveDelivery
  module_function

  # resolve(global_store:, project_roots:, session:, ttl:, now:) -> intent_dir or nil.
  # Nil for zero matches or more than one: a session holding two live locks
  # at once is a state nothing downstream may guess through (row 4.25).
  def resolve(global_store:, project_roots:, session:, ttl: Lock::TTL_SECONDS, now: Time.now)
    held = candidate_intent_dirs(global_store: global_store, project_roots: project_roots)
           .uniq
           .select { |dir| held_live?(dir, session: session, ttl: ttl, now: now) }
    held.size == 1 ? held.first : nil
  end

  # Every intent directory under the global store or a configured project
  # root that carries a delivery.lock file, unparsed. One Dir.glob per root
  # (row 4.27): the global store's intents sit directly under store/, a
  # project root's intents sit two levels down, under <root>/<slug>/store/.
  def candidate_intent_dirs(global_store:, project_roots:)
    dirs = []
    dirs.concat(Dir.glob(File.join(global_store.to_s, "*", "delivery.lock"))) unless blank?(global_store)
    Array(project_roots).each do |root|
      next if blank?(root)

      dirs.concat(Dir.glob(File.join(root.to_s, "*", "store", "*", "delivery.lock")))
    end
    dirs.map { |lock_path| File.dirname(lock_path) }
  end

  # Live and held by this session: a fresh (non-expired) lock whose owner or
  # delegate list names this session. A torn or unparseable lock is skipped,
  # never raised (row 4.26): a module a hook depends on must fail as quietly
  # as the hook itself does.
  def held_live?(intent_dir, session:, ttl:, now:)
    return false unless Lock.fresh?(intent_dir, ttl: ttl, now: now)

    Lock.holds?(intent_dir, session: session)
  rescue StandardError
    false
  end

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  DEFAULT_PROJECT_ROOTS = ["~/.plastic/projects"].freeze

  # The configured project roots (344 n2, D6): the `project_roots` list in
  # `<plastic_home>/config.yml`, each expanded, or the default
  # `~/.plastic/projects` when the key is absent or the file cannot be read
  # or parsed. Never raises: a broken config.yml must never crash a hook on
  # every prompt.
  def project_roots(plastic_home)
    path = File.join(plastic_home.to_s, "config.yml")
    data = File.exist?(path) ? YAML.safe_load(File.read(path)) : nil
    roots = data.is_a?(Hash) ? data["project_roots"] : nil
    roots = DEFAULT_PROJECT_ROOTS unless roots.is_a?(Array) && !roots.empty?
    roots.map { |root| File.expand_path(root.to_s) }
  rescue StandardError
    DEFAULT_PROJECT_ROOTS.map { |root| File.expand_path(root) }
  end

  # resolve_by_short_session(...) -> intent_dir or nil (344 n2). The tmp dir
  # name is the short session id, while lock owners and delegates carry full
  # ids, so this matches a lock whose owner or a delegate session STARTS WITH
  # the short id. Nil for zero or more than one match, mirroring resolve's
  # own uniqueness rule: an ambiguous short id names nothing downstream may
  # guess through.
  def resolve_by_short_session(global_store:, project_roots:, short_session:,
                               ttl: Lock::TTL_SECONDS, now: Time.now)
    held = candidate_intent_dirs(global_store: global_store, project_roots: project_roots)
           .uniq
           .select { |dir| held_live_by_short?(dir, short_session: short_session, ttl: ttl, now: now) }
    held.size == 1 ? held.first : nil
  end

  def held_live_by_short?(intent_dir, short_session:, ttl:, now:)
    return false unless Lock.fresh?(intent_dir, ttl: ttl, now: now)

    data = Lock.read(intent_dir)
    return false unless data.is_a?(Hash)

    sessions = [data["owner_session"]] + Array(data["delegates"])
    sessions.compact.map(&:to_s).any? { |session| session.start_with?(short_session.to_s) }
  rescue StandardError
    false
  end
end
