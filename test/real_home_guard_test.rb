# encoding: UTF-8
# frozen_string_literal: true

require_relative "test_helper"
require "etc"
require "tmpdir"

load File.expand_path("../bin/verify-change", __dir__)

# Real-home guard (intent 363). The incident: `bin/verify-change` spawned every
# gate child with the session's own HOME, and the mutation step mutates
# scripts/lib/cli/legacy.rb, where `@runner = runner || DEFAULT_RUNNER` decides
# whether an installer verb runs its injected test runner or spawns the real
# scripts/install.rb. A mutant that defeats the injection turns a hermetic unit
# test into a real install, and eleven of them landed in the owner's
# ~/.plastic and ~/.claude before anyone noticed.
#
# Two halves, the same shape as test/hermeticity_guard_test.rb. The static scan
# catches a test that spawns an installer or the launcher without a throwaway
# HOME. The dynamic backstop catches everything the scan cannot see, including
# a spawn a mutant invented, by fingerprinting the real home before the suite
# runs and again after it.
class RealHomeGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SPAWN = /\bsystem\(|Open3\.|IO\.popen|Process\.spawn/
  VERB = %r{(?:"|'|/)(?:install|uninstall|update|rollback)\.rb(?:"|')|"scripts", "(?:install|uninstall|update|rollback)\.rb"}
  LAUNCHER = %r{bin/plastic(?![-.\w])|"bin", "plastic"}
  INSTALLER_PATH = %r{bin/plastic(?![-.\w])|"bin", "plastic"|(?:install|uninstall|update|rollback)\.rb}
  CONSTANT = /^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.+)$/

  # The passwd entry, not ENV["HOME"], so the guard still watches the machine's
  # own home when the suite itself runs under a throwaway one.
  REAL_HOME = Etc.getpwuid(Process.uid).dir

  # What an install or an uninstall changes and a working session never does.
  def self.fingerprint
    files = %w[.plastic/versions.json .plastic/VERSION .plastic/manifest.json]
    directories = %w[.claude/hooks .claude/skills]
    files.to_h { |path| [path, (File.read(File.join(REAL_HOME, path)) rescue nil)] }
      .merge(directories.to_h { |path| [path, (Dir.children(File.join(REAL_HOME, path)).sort rescue nil)] })
  end

  BEFORE = fingerprint.freeze

  # Constants naming an installer script or the launcher, so a spawn through
  # LAUNCHER reads as an installer spawn even though the line holds no path.
  def installer_constants(source)
    source.scan(CONSTANT).select { |_name, value| value.match?(INSTALLER_PATH) }.map(&:first)
  end

  def installer_spawns(source)
    names = installer_constants(source)
    by_constant = names.empty? ? nil : /\b(?:#{names.join("|")})\b/
    source.lines.each_with_index.select do |line, _number|
      line.match?(SPAWN) &&
        (line.match?(VERB) || line.match?(LAUNCHER) || (by_constant && line.match?(by_constant)))
    end.map { |_line, number| number + 1 }
  end

  def test_the_detector_reads_a_literal_installer_spawn
    source = %(Open3.capture3(env, RbConfig.ruby, File.join(REPO, "scripts", "install.rb"))\n)

    assert_equal [1], installer_spawns(source)
  end

  def test_the_detector_reads_a_spawn_through_a_launcher_constant
    source = %(LAUNCHER = File.join(ROOT, "bin", "plastic")\nOpen3.capture3(LAUNCHER, "help")\n)

    assert_equal [2], installer_spawns(source)
  end

  def test_the_detector_ignores_an_installer_path_that_is_only_asserted_on
    source = %(assert_path_exists File.join(REPO, "bin/plastic")\n)

    assert_empty installer_spawns(source)
  end

  def test_the_detector_ignores_a_neighbouring_binary_with_a_longer_name
    source = %(CENSUS = File.join(REPO, "bin/plastic-skill-census")\nOpen3.capture3(CENSUS, "--json")\n)

    assert_empty installer_spawns(source)
  end

  def test_every_test_that_spawns_an_installer_gives_it_a_throwaway_home
    offenders = Dir[File.join(ROOT, "test", "**", "*_test.rb")].sort.reject do |path|
      source = File.read(path)
      installer_spawns(source).empty? || source.include?(%("HOME"))
    end

    assert_empty offenders.map { |path| path.delete_prefix("#{ROOT}/") },
      "these tests spawn an installer or the launcher without injecting HOME"
  end

  def planned_steps(sandbox)
    VerifyChange.new([], root: ROOT, sandbox: sandbox)
      .plan(changed: ["scripts/lib/cli/legacy.rb", "test/cli/legacy_test.rb"],
        extra_tests: [], base: "HEAD", rails: false)
  end

  def test_every_gate_step_runs_under_the_sandbox_home
    sandbox = {"HOME" => "/nowhere/home", "PLASTIC_TMP" => "/nowhere/tmp"}
    plan = planned_steps(sandbox)
    steps = plan.steps + [plan.lint_decision.step].compact

    refute_empty steps
    steps.each do |step|
      assert_equal "/nowhere/home", step.env["HOME"], "#{step.title} runs under the ambient home"
      assert_equal "/nowhere/tmp", step.env["PLASTIC_TMP"], "#{step.title} runs under the ambient tmp dir"
    end
  end

  def test_the_step_environment_keeps_its_own_variables
    plan = planned_steps({"HOME" => "/nowhere/home", "PLASTIC_TMP" => "/nowhere/tmp"})
    tests = plan.steps.find { |step| step.title == VerifyChange::TESTS_STEP }

    assert_equal "1", tests.env["COVERAGE"]
  end

  def test_the_default_sandbox_is_a_fresh_directory_outside_the_real_home
    subject = VerifyChange.new([], root: ROOT)
    home = subject.sandbox["HOME"]

    refute home.start_with?(REAL_HOME), "the sandbox home sits inside #{REAL_HOME}"
    assert_empty Dir.children(home)
  ensure
    subject&.discard_sandbox
  end

  def test_the_sandbox_is_discarded_after_the_run
    subject = VerifyChange.new([], root: ROOT)
    home = subject.sandbox["HOME"]
    subject.discard_sandbox

    refute_path_exists home
  end

  Minitest.after_run do
    after = fingerprint
    if after != BEFORE
      changed = after.keys.reject { |key| after[key] == BEFORE[key] }
      warn "REAL HOME VIOLATION: the suite changed #{changed.join(", ")} under #{REAL_HOME}. " \
           "A test or a mutant spawned an installer against the machine's own home."
      exit 1
    end
  end
end
