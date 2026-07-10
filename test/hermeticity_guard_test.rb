require "minitest/autorun"
require "json"

# Hermeticity guard (intent 108; validates 73c1a). The 107/110 incidents:
# a bridge test writing with the ambient real session id clobbered the live
# session's /tmp bridge mid-delivery. Contract: any test file that WRITES
# bridge state must isolate the tmp dir (PLASTIC_TMP env injection for
# spawned processes, or the tmp:/Dir.mktmpdir seams in-process), and any test
# file exercising arm/derive must not leak the ambient CLAUDE_CODE_SESSION_ID
# into those writes.
#
# This file is a STATIC guard (source scans only). It cannot catch a live
# Worktree.provision call resolving against the real ~/.plastic (that is how
# 166 got bitten). See test/worktree_hermeticity_test.rb (intent 169) for the
# runtime behavioral counterpart.
class HermeticityGuardTest < Minitest::Test
  WRITERS = /Bridge\.(arm_auto|arm_guided|derive|write|disarm_auto|repair_lock)\b/.freeze
  ISOLATION = /PLASTIC_TMP|tmp:\s|Dir\.mktmpdir/.freeze

  def test_every_bridge_writing_test_isolates_its_tmp
    offenders = Dir[File.expand_path("../*_test.rb", __FILE__)].select do |f|
      next false if File.basename(f) == File.basename(__FILE__)
      src = File.read(f)
      src.match?(WRITERS) && !src.match?(ISOLATION)
    end
    assert_empty offenders,
      "these tests write bridge state without tmp isolation: #{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  def test_every_arm_exercising_test_clears_the_ambient_session_id
    offenders = Dir[File.expand_path("../*_test.rb", __FILE__)].select do |f|
      next false if File.basename(f) == File.basename(__FILE__)
      src = File.read(f)
      src.match?(/Bridge\.(arm_auto|arm_guided)\b/) &&
        !src.include?("CLAUDE_CODE_SESSION_ID")
    end
    assert_empty offenders,
      "these tests arm without handling the ambient session id: #{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  # arm (and, since intent 136, repair_lock) run the REAL Worktree.provision,
  # whose plastic_home derives from HOME: unneutralized, a test plants a store
  # worktree in the LIVE ~/.plastic (observed: ~/.plastic/.worktrees/{52,80,96}
  # --demo). Every arm- or repair_lock-exercising test must stub provision or
  # isolate HOME for spawned arms/repairs.
  def test_every_arm_exercising_test_neutralizes_worktree_provision
    offenders = Dir[File.expand_path("../*_test.rb", __FILE__)].select do |f|
      next false if File.basename(f) == File.basename(__FILE__)
      src = File.read(f)
      src.match?(/Bridge\.(arm_auto|arm_guided|repair_lock)\b/) &&
        !src.match?(/define_singleton_method\(:provision|with_worktree\(:provision|"HOME"\s*=>/)
    end
    assert_empty offenders,
      "these tests arm/repair without stubbing Worktree.provision or isolating HOME: " \
      "#{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  # hook-session-start and hook-gate-check WRITE bridge state (derive /
  # last_activity) keyed by the ambient session id. A test that spawns either
  # without env isolation clobbers the live session's /tmp bridge (the exact
  # 107/110 incident, reproduced by deprecation_display_test before this
  # guard). Spawning tests must inject PLASTIC_TMP.
  def test_every_bridge_writing_hook_spawn_isolates_its_tmp
    offenders = Dir[File.expand_path("../*_test.rb", __FILE__)].select do |f|
      next false if File.basename(f) == File.basename(__FILE__)
      src = File.read(f)
      src.match?(/hook-(session-start|gate-check)/) &&
        src.match?(/Open3|IO\.popen|\bsystem\(/) &&
        !src.include?("PLASTIC_TMP")
    end
    assert_empty offenders,
      "these tests spawn a bridge-writing hook without PLASTIC_TMP isolation: " \
      "#{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  # Dynamic backstop (verifier note): snapshot the REAL /tmp bridge files when
  # this file loads and compare after the whole run. A suite that mutates a
  # live session's /tmp bridge fails here even if the static scan missed it.
  # Only meaningful when the suite runs with PLASTIC_TMP isolated away from
  # /tmp, which is how AGENTS.md says to run it.
  REAL_TMP_BRIDGES = Dir["/tmp/plastic-*.json"].sort.map do |f|
    [f, (File.read(f) rescue nil)]
  end.freeze

  Minitest.after_run do
    now = Dir["/tmp/plastic-*.json"].sort.map { |f| [f, (File.read(f) rescue nil)] }
    if ENV["PLASTIC_TMP"].to_s.strip.empty? || ENV["PLASTIC_TMP"] == "/tmp"
      # Suite ran against the real /tmp: the snapshot cannot distinguish suite
      # writes from the session's own; skip the comparison.
    elsif now != REAL_TMP_BRIDGES
      warn "HERMETICITY VIOLATION: the suite changed /tmp/plastic-*.json " \
           "(live session bridges). Before: #{REAL_TMP_BRIDGES.map(&:first)}. " \
           "After: #{now.map(&:first)}."
      exit 1
    end
  end
end
