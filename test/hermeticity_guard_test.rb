require "minitest/autorun"
require "json"
require "tmpdir"

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
  LOCK_VISIBILITY_ROOTS = %w[
    scripts/lib/lock.rb
    scripts/plastic-lock
    scripts/dashboard.rb
  ].freeze

  # Strip syntax that can separate adjacent path components in Ruby source,
  # then allow a short punctuation-only gap. This catches both a contiguous
  # path and constructions such as File.join(Dir.home, ".codex", "sessions")
  # without flagging unrelated prose that happens to mention both words.
  def transcript_lookup_markers(source)
    compact = source.delete("'\" \t\r\n")
    markers = []
    markers << ".claude/projects" if compact.match?(/\.claude[^[:alnum:]_]{0,24}projects/)
    markers << ".codex/sessions" if compact.match?(/\.codex[^[:alnum:]_]{0,24}sessions/)
    markers << "rollout-" if source.include?("rollout-")
    markers
  end

  def local_dependency_closure(root, roots)
    root = File.expand_path(root)
    root_prefix = "#{root}#{File::SEPARATOR}"
    pending = roots.map { |path| File.expand_path(path, root) }
    visited = {}

    until pending.empty?
      path = pending.shift
      next unless path.start_with?(root_prefix) && File.file?(path)
      next if visited[path]

      visited[path] = true
      File.read(path).scan(/require_relative\s*(?:\(\s*)?["']([^"']+)["']/).flatten.each do |relative|
        candidate = File.expand_path(relative, File.dirname(path))
        candidate = "#{candidate}.rb" unless File.file?(candidate)
        pending << candidate if candidate.start_with?(root_prefix) && File.file?(candidate)
      end
    end

    visited.keys.sort
  end

  def test_lock_visibility_dependency_closure_follows_local_helpers
    root = File.expand_path("..", __dir__)
    relative_paths = local_dependency_closure(root, LOCK_VISIBILITY_ROOTS)
      .map { |path| path.delete_prefix("#{root}#{File::SEPARATOR}") }

    %w[scripts/lib/bridge.rb scripts/lib/worktree.rb scripts/doctor.rb].each do |expected|
      assert_includes relative_paths, expected
    end
  end

  def test_lock_visibility_dependency_closure_cannot_escape_project_root
    Dir.mktmpdir("lock-visibility-closure") do |parent|
      root = File.join(parent, "project")
      Dir.mkdir(root)
      File.write(File.join(parent, "outside.rb"), "TRANSCRIPT_LOOKUP = true\n")
      File.write(File.join(root, "entry.rb"), "require_relative '../outside'\n")
      closure = local_dependency_closure(root, ["entry.rb", "../outside.rb"])

      assert_equal [File.join(root, "entry.rb")], closure
    end
  end

  def test_transcript_lookup_detection_catches_contiguous_paths
    source = 'File.read(File.join(Dir.home, ".codex/sessions", "rollout-123.jsonl"))'

    assert_equal [".codex/sessions", "rollout-"], transcript_lookup_markers(source)
  end

  def test_transcript_lookup_detection_catches_split_file_join_components
    claude = "File.join(Dir.home, '.claude', 'projects', session)"
    codex = 'File.join(Dir.home, ".codex", "sessions", year, "rollout-#{id}.jsonl")'

    assert_equal [".claude/projects"], transcript_lookup_markers(claude)
    assert_equal [".codex/sessions", "rollout-"], transcript_lookup_markers(codex)
  end

  def test_transcript_lookup_detection_ignores_unrelated_component_names
    source = 'dashboard.projects.map { |project| project.sessions }'

    assert_empty transcript_lookup_markers(source)
  end

  def test_lock_visibility_does_not_search_ambient_transcript_stores
    root = File.expand_path("..", __dir__)
    offenders = local_dependency_closure(root, LOCK_VISIBILITY_ROOTS).flat_map do |path|
      relative_path = path.delete_prefix("#{root}#{File::SEPARATOR}")
      transcript_lookup_markers(File.read(path)).map { |marker| "#{relative_path}: #{marker}" }
    end

    assert_empty offenders,
      "lock visibility must use durable lock state, not ambient transcript stores: #{offenders.join(', ')}"
  end

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
