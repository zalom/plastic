# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"

require_relative "../scripts/doctor"

# Coverage for the doctor/doctor_core split (intent 228): scripts/doctor.rb
# reopens the Doctor class defined in scripts/lib/doctor_core.rb, so the
# SessionStart hook can require only the core file instead of the whole
# diagnostic engine. Four tests: output identity between the core-only load
# and the full Doctor (T1), an exact-set assertion of which repo files the
# core require is allowed to pull in, so a new file cannot quietly re-attach
# itself to the boot path (T2), a byte-size regrowth budget as a secondary
# guard (T3), and a guard against a second hand-kept list of which checks
# are core (T4).
#
# Hermetic throughout: every fixture lives in a Dir.mktmpdir, every subprocess
# is launched with an explicit absolute path, no eval, no ENV or
# global-constant seam, no network, no reads of the real ~/.plastic.
class DoctorCoreSplitTest < Minitest::Test
  ROOT = File.expand_path("../../", __FILE__)
  DOCTOR_CORE_PATH = File.join(ROOT, "scripts/lib/doctor_core.rb")
  DOCTOR_PATH = File.join(ROOT, "scripts/doctor.rb")

  def setup
    @dir = Dir.mktmpdir("plastic-doctor-core-split")
    @home = File.join(@dir, "home")
    @claude_dir = File.join(@dir, "claude")
    @codex_dir = File.join(@dir, "codex")
    @codex_home = File.join(@dir, "codex-home")
    FileUtils.mkdir_p([@home, @claude_dir, @codex_dir, @codex_home])
    build_fixture_store
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A liveness-surface fixture good enough to exercise every branch
  # run_core_checks reaches for both agents without raising. It does not need
  # to come out "pass": T1 only needs the SAME result from both halves of
  # Doctor, whatever that result is.
  def build_fixture_store
    FileUtils.mkdir_p(File.join(@claude_dir, "hooks"))
    skill_dir = File.join(@claude_dir, "skills", "plastic-doctor")
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, "SKILL.md"), "# skill")
    agents_dir = File.join(@claude_dir, "agents")
    FileUtils.mkdir_p(agents_dir)
    File.write(File.join(agents_dir, "plastic-enforcer.md"),
      "---\nname: plastic-enforcer\nmodel: opus\n---\n# agent\n")

    File.write(File.join(@home, "VERSION"), "1.0.0")
    File.write(File.join(@home, "PLASTIC.md"), "# Plastic\n")
    scripts_dir = File.join(@home, "scripts")
    FileUtils.mkdir_p(scripts_dir)
    Doctor::REQUIRED_SCRIPTS.each do |script|
      path = File.join(scripts_dir, script)
      File.write(path, "#!/usr/bin/env ruby\n")
      File.chmod(0o755, path)
    end
    File.write(File.join(@home, "projects.yml"), "projects: {}\n")
    File.write(File.join(@home, "INDEX.md"), "# Index\n")
  end

  def fixture_agents_literal
    <<~RUBY
      {
        "claude" => { name: "Claude Code", dir: #{@claude_dir.inspect} },
        "codex" => { name: "Codex CLI", dir: #{@codex_dir.inspect}, home_dir: #{@codex_home.inspect} },
      }
    RUBY
  end

  # Both sides of T1 use the exact same fake runner behavior: no real codex
  # binary, no PATH mutation. FAKE_RUNNER_SOURCE is the literal Ruby text
  # embedded verbatim into the subprocess script in run_core_only_subprocess;
  # fake_runner below is the same behavior as a real lambda for the in-process
  # side. Neither process ever calls eval.
  FAKE_RUNNER_SOURCE = '->(args) { ["codex-cli 1.0.0", true] }'

  def fake_runner
    ->(args) { ["codex-cli 1.0.0", true] }
  end

  def full_doctor
    Doctor.new(
      plastic_home: @home,
      agents: { "claude" => { name: "Claude Code", dir: @claude_dir },
                "codex" => { name: "Codex CLI", dir: @codex_dir, home_dir: @codex_home } },
      runner: fake_runner
    )
  end

  # T1: a clean subprocess that requires ONLY scripts/lib/doctor_core.rb must
  # produce byte-identical run_core_checks output to the full Doctor loaded
  # via scripts/doctor.rb, for both agents. This is the real catcher for a
  # core method that silently depends on a non-core constant: Ruby resolves
  # constants at call time, so such a bug would show only at run, only on the
  # boot path.
  def test_core_only_run_matches_full_doctor_for_claude_and_codex
    %w[claude codex].each do |agent_key|
      core_only = run_core_only_subprocess(agent_key)
      full = JSON.parse(JSON.generate(full_doctor.run_core_checks(agent_key)))

      blank_timestamp!(core_only)
      blank_timestamp!(full)

      assert_equal full, core_only,
        "core-only run_core_checks(#{agent_key.inspect}) diverged from the full Doctor's output"
    end
  end

  def run_core_only_subprocess(agent_key)
    script = <<~RUBY
      require "json"
      require #{DOCTOR_CORE_PATH.inspect}
      agents = #{fixture_agents_literal}
      runner = #{FAKE_RUNNER_SOURCE}
      doctor = Doctor.new(plastic_home: #{@home.inspect}, agents: agents, runner: runner)
      result = doctor.run_core_checks(#{agent_key.inspect})
      puts JSON.generate(result)
    RUBY
    script_path = File.join(@dir, "core_only_#{agent_key}.rb")
    File.write(script_path, script)
    out, err, status = Open3.capture3("ruby", script_path)
    assert status.success?, "core-only subprocess for #{agent_key.inspect} failed: #{err}"
    JSON.parse(out)
  end

  def blank_timestamp!(hash)
    hash["timestamp"] = "FIXED" if hash.is_a?(Hash) && hash.key?("timestamp")
  end

  # --- T2 and T3 share one clean-subprocess measurement of everything loaded
  # when only scripts/lib/doctor_core.rb is required. ---

  # The complete, exact set of repo-file basenames the boot path is allowed
  # to load. This is an allow-list, not a deny-list: anything new that
  # attaches itself to scripts/lib/doctor_core.rb's require chain fails this
  # test by name, with no hand-kept list of "known non-core libs" for a
  # human to keep in sync as the codebase grows.
  CORE_REQUIRE_ALLOWED_BASENAMES = %w[doctor_core.rb hook_registry.rb].freeze

  def loaded_after_core_require
    return @loaded_after_core_require if defined?(@loaded_after_core_require)

    script = <<~RUBY
      require "json"
      before = $LOADED_FEATURES.dup
      require #{DOCTOR_CORE_PATH.inspect}
      loaded = ($LOADED_FEATURES.dup - before).select { |f| f.end_with?(".rb") }
      info = loaded.map { |f| { "path" => f, "basename" => File.basename(f), "bytes" => File.size(f) } }
      puts JSON.generate(info)
    RUBY
    script_path = File.join(@dir, "loaded_features_probe.rb")
    File.write(script_path, script)
    out, err, status = Open3.capture3("ruby", script_path)
    assert status.success?, "loaded-features probe subprocess failed: #{err}"
    @loaded_after_core_require = JSON.parse(out)
  end

  # T2: the set of repo-file basenames loaded when only
  # scripts/lib/doctor_core.rb is required must be EXACTLY
  # CORE_REQUIRE_ALLOWED_BASENAMES, no more and no less. Unlike a hand-kept
  # deny-list, this catches any future file by name, including ones that did
  # not exist when this test was written.
  def test_core_require_loads_exactly_the_allowed_repo_files
    plastic_files = loaded_after_core_require.select { |i| i["path"].start_with?(ROOT) }
    basenames = plastic_files.map { |i| i["basename"] }.sort

    extra = basenames - CORE_REQUIRE_ALLOWED_BASENAMES
    missing = CORE_REQUIRE_ALLOWED_BASENAMES - basenames

    assert_empty extra,
      "scripts/lib/doctor_core.rb's require chain now pulls in #{extra.join(', ')}, which " \
      "is not on the boot-path allow-list (#{CORE_REQUIRE_ALLOWED_BASENAMES.join(', ')}). " \
      "If this file genuinely belongs on the boot path, add it to " \
      "CORE_REQUIRE_ALLOWED_BASENAMES deliberately in a new intent; otherwise it has " \
      "re-attached itself to the boot path and must be removed from the require chain."
    assert_empty missing,
      "scripts/lib/doctor_core.rb no longer requires #{missing.join(', ')}, which the boot " \
      "path is expected to depend on."
  end

  # T3: a byte-size regrowth budget as a secondary guard (modeled on
  # test/plastic_core_budget_test.rb). T2 already pins the exact file set, so
  # this only catches one of the two allowed files quietly bloating in place.
  def test_core_require_stays_under_the_boot_path_byte_budget
    plastic_files = loaded_after_core_require.select { |i| i["path"].start_with?(ROOT) }

    total_bytes = plastic_files.sum { |i| i["bytes"] }
    assert_operator total_bytes, :<=, 65_000,
      "the doctor boot path now loads #{total_bytes} bytes of repo files; ceiling is 65,000. " \
      "If this growth is intentional, justify it in a new intent before raising the ceiling."
  end

  # T4: the core-check name set named inside run_core_checks must not appear
  # as a hand-written literal list (array, hash, or constant) anywhere else
  # under scripts/, so a future change cannot plant a second "which checks
  # are core" list beside the real one. The scan covers both *.rb files and
  # the extensionless executables under scripts/ (detected by a Ruby
  # shebang), since a duplicate list is at least as likely to be planted in
  # a boot-side executable script as in a .rb file.
  def test_core_check_list_appears_in_exactly_one_place
    core_source = File.read(DOCTOR_CORE_PATH)
    run_core_checks_body = core_source[/def run_core_checks\(agent_key\).*?\n  end/m]
    refute_nil run_core_checks_body, "expected to find run_core_checks in #{DOCTOR_CORE_PATH}"

    check_names = run_core_checks_body.scan(/all_checks \+= (check_\w+)/).flatten.uniq
    refute_empty check_names, "expected at least one check_* call inside run_core_checks"

    offenders = scripts_scan_targets.reject { |p| p == DOCTOR_CORE_PATH }.select do |path|
      content = File.read(path)
      literal_list_with_all_names?(content, check_names)
    end

    assert_empty offenders,
      "found a hand-kept duplicate of the core-check name list outside doctor_core.rb: #{offenders.join(', ')}"
  end

  # Every *.rb file under scripts/, plus every extensionless file under
  # scripts/ whose first line is a Ruby shebang. Detecting executables by
  # shebang (rather than by hardcoding a specific script's name) keeps the
  # scan itself honest: it derives what counts as Ruby source instead of
  # hand-listing it.
  def scripts_scan_targets
    rb_files = Dir.glob(File.join(ROOT, "scripts", "**", "*.rb"))
    executables = Dir.glob(File.join(ROOT, "scripts", "**", "*")).select do |path|
      File.file?(path) && File.extname(path).empty? && ruby_shebang?(path)
    end
    (rb_files + executables).uniq
  end

  def ruby_shebang?(path)
    first_line = File.open(path) { |f| f.gets }
    return false unless first_line

    first_line.start_with?("#!") && first_line.include?("ruby")
  rescue StandardError
    false
  end

  # A literal Ruby list (array or %w[...]) that names every one of check_names
  # as a bare word or string/symbol, all inside one bracketed literal.
  def literal_list_with_all_names?(content, check_names)
    content.scan(/(?:%w\[|\[)([^\]]*)\]/m).any? do |(body)|
      check_names.all? { |name| body.include?(name) }
    end
  end
end
