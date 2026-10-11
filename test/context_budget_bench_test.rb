# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "support/child_process"
require "rbconfig"
require "yaml"
require "stringio"

require_relative "../bin/lib/context_budget"

# The context budget bench. The core block stays under 8,192 bytes and the whole
# per-boot doctrine read under 15,000. These tests pin what the bench measures,
# that it measures it hermetically, and that a crossed ceiling turns the suite red.
#
# Hermetic and DI throughout: every fixture is a Dir.mktmpdir with its own HOME
# and PLASTIC_HOME, the boot subprocess's env is injectable and asserted, and no
# case reads the real ~/.plastic or ~/.claude.

# One real install, shared by every case below that reads a fixture or boots
# it without mutating it. A real boot is read-only against the fixture it
# boots, so sharing it here costs nothing; only the two cases that swap in a
# broken repo or an over-budget core build their own, throwaway fixture.
module ContextBudgetSharedFixture
  REPO = File.expand_path("../../", __FILE__)

  def self.fixture
    @fixture ||= begin
      dir = Dir.mktmpdir("plastic-bench-shared-fixture")
      Minitest.after_run { FileUtils.remove_entry(dir) }
      ContextBudget::Fixture.build(dir: dir, repo: REPO)
    end
  end

  # A copy of the shared install, for the one case that must mutate its
  # PLASTIC.md (the over-budget-core proof): a file copy is far cheaper than
  # a second real install, and the shared fixture stays untouched for the
  # cases after it.
  def self.clone(label)
    dir = Dir.mktmpdir(label)
    Minitest.after_run { FileUtils.remove_entry(dir) }
    FileUtils.cp_r("#{fixture.home}/.", dir)
    home = File.realpath(dir)
    ContextBudget::Fixture.new(home: home, plastic_home: File.join(home, ".plastic"),
      index: fixture.index.sub(fixture.home, home), project_dir: File.join(home, "project"))
  end
end

# The estimator, the skill split, the catalog and the median: pure functions over
# strings and a synthetic two-skill tree.
class ContextBudgetMeasureTest < Minitest::Test
  def test_measure_counts_tokens_as_words_times_one_point_three
    body = (["word"] * 40).join(" ")
    m = ContextBudget.measure(body)

    assert_equal 1, m.lines
    assert_equal 40, m.words
    assert_equal (40 * 1.3).round, m.tokens
    assert_equal body.bytesize, m.bytes
    assert_equal (body.bytesize / 4.0).round, m.tokens_by_bytes
  end

  # A budget in bytes must count bytes. Multi-byte doctrine (the em dashes and
  # arrows PLASTIC.md is full of) costs more than its character count.
  def test_measure_counts_bytes_not_characters
    body = "é" * 10
    m = ContextBudget.measure(body)

    assert_equal 20, m.bytes
    refute_equal body.length, m.bytes
  end

  def test_measure_counts_the_lines_of_a_text
    assert_equal 3, ContextBudget.measure("a\nb\nc\n").lines
  end

  def test_split_skill_separates_the_frontmatter_from_the_body
    content = "---\nname: x\ndescription: y\n---\n\n# Body\n\ntext\n"
    frontmatter, body = ContextBudget.split_skill(content)

    assert_includes frontmatter, "name: x"
    refute_includes body, "description:"
    assert_includes body, "# Body"
  end

  def test_split_skill_treats_a_file_without_frontmatter_as_all_body
    frontmatter, body = ContextBudget.split_skill("# Just a body\n")

    assert_nil frontmatter
    assert_equal "# Just a body\n", body
  end

  def build_skill_tree(dir)
    a = File.join(dir, "skills", "alpha")
    b = File.join(dir, "skills", "beta")
    FileUtils.mkdir_p(File.join(a, "references"))
    FileUtils.mkdir_p(File.join(b, "evals"))

    File.write(File.join(a, "SKILL.md"), <<~MD)
      ---
      name: plastic-alpha
      description: One line of description.
      user-invocable: true
      ---

      body of alpha
    MD
    # A wrapped (multi-line) description: the shape a naive line regex truncates.
    File.write(File.join(b, "SKILL.md"), <<~MD)
      ---
      name: plastic-beta
      description: >-
        First half of the description
        and its second half.
      ---

      body of beta, which is longer than alpha's body by some margin
    MD
    File.write(File.join(a, "references", "chapter.md"), "x" * 5000)
    File.write(File.join(b, "evals", "evals.json"), "{}")
  end

  # The catalog is what the harness loads at boot: the name and description
  # VALUES, YAML-parsed, not the raw frontmatter lines and not the keys.
  def test_skill_catalog_counts_name_and_description_values
    Dir.mktmpdir("plastic-bench-catalog") do |dir|
      build_skill_tree(dir)

      expected = Dir.glob(File.join(dir, "skills", "*", "SKILL.md")).sum do |path|
        frontmatter, = ContextBudget.split_skill(File.read(path))
        data = YAML.safe_load(frontmatter.to_s) || {}
        data["name"].to_s.bytesize + data["description"].to_s.bytesize
      end

      assert_operator expected, :>, 0
      assert_equal expected, ContextBudget.skill_catalog_bytes(repo: dir)
    end
  end

  def test_skill_catalog_keeps_a_wrapped_description_whole
    Dir.mktmpdir("plastic-bench-wrapped") do |dir|
      build_skill_tree(dir)
      beta = File.join(dir, "skills", "beta", "SKILL.md")
      frontmatter, = ContextBudget.split_skill(File.read(beta))
      description = (YAML.safe_load(frontmatter) || {})["description"].to_s

      assert_includes description, "second half",
        "a wrapped description must be parsed whole, not truncated at the first line"
    end
  end

  # references/*.md and evals/*.json are not read at boot and are not skill bodies.
  def test_skill_body_sizes_count_only_skill_md_bodies
    Dir.mktmpdir("plastic-bench-bodies") do |dir|
      build_skill_tree(dir)
      sizes = ContextBudget.skill_body_sizes(repo: dir)

      assert_equal 2, sizes.length, "one body per SKILL.md, never a reference or an eval"
      refute_includes sizes, 5000, "a references/*.md file must not be counted as a skill body"
      sizes.each do |size|
        assert_operator size, :<, 200, "a body must exclude its frontmatter"
      end
    end
  end

  def test_median_of_an_odd_count_is_the_middle_value
    assert_equal 3, ContextBudget.median([5, 1, 3])
  end

  def test_median_of_an_even_count_is_the_mean_of_the_middle_two
    assert_equal 5, ContextBudget.median([2, 4, 6, 8])
  end

  def test_median_of_nothing_is_zero
    assert_equal 0, ContextBudget.median([])
  end
end

# Fixture.build: a real installed Plastic in a tmp home. A fixture without
# ~/.claude boots degraded (doctor_core.rb:307-314 short-circuits and the banner
# reads "error"), which measures something no real session sees.
class ContextBudgetFixtureTest < Minitest::Test
  REPO = ContextBudgetSharedFixture::REPO

  # The four tests below only read what one real install produced; they share
  # the one install every other read-only case in this file shares.
  def fixture = ContextBudgetSharedFixture.fixture

  def test_build_runs_the_real_installer
    assert File.file?(File.join(fixture.plastic_home, "VERSION")),
      "the fixture must carry an installed VERSION"
    refute_empty Dir.glob(File.join(fixture.home, ".claude", "hooks", "*")),
      "the fixture must carry installed Claude hook launchers, or the boot measures a degraded install"
  end

  def test_build_copies_the_repos_own_core_block
    assert_equal File.size(File.join(REPO, "PLASTIC.md")),
      File.size(File.join(fixture.plastic_home, "PLASTIC.md")),
      "the fixture must measure the repo's core block, never a stale one"
  end

  # On macOS Dir.pwd resolves /var to /private/var; without realpath the hook's
  # cwd.start_with?(project_path) test silently misses and the project banner
  # disappears from the measured context.
  def test_build_realpaths_the_project_directory
    assert_equal File.realpath(fixture.project_dir), fixture.project_dir
    assert_equal File.realpath(fixture.home), fixture.home
  end

  def test_build_stays_inside_the_given_directory
    env = ContextBudget.child_env(fixture)

    %w[HOME PLASTIC_HOME PLASTIC_TMP].each do |key|
      assert env[key].start_with?(fixture.home),
        "#{key} (#{env[key]}) must live inside the fixture, never in the real home"
    end
  end

  def test_build_raises_when_the_installer_fails
    Dir.mktmpdir("plastic-bench-broken") do |dir|
      Dir.mktmpdir("plastic-bench-norepo") do |fake_repo|
        error = assert_raises(RuntimeError) do
          ContextBudget::Fixture.build(dir: dir, repo: fake_repo)
        end
        assert_match(/install/i, error.message)
      end
    end
  end
end

class ContextBudgetCeilingTest < Minitest::Test
  REPO = ContextBudgetSharedFixture::REPO

  # The three tests below only read a fixture's paths or inject a fake boot
  # runner; none of them touches the filesystem the fixture installed into,
  # so they share the one real install every other read-only case shares.
  def fixture = ContextBudgetSharedFixture.fixture

  # The ceilings are fixed numbers; changing one must be argued, not typed.
  def test_ceilings_are_the_ruled_numbers
    assert_equal 8_192, ContextBudget::CEILINGS[:core]
    assert_equal 15_000, ContextBudget::CEILINGS[:boot]
    assert_equal 17_500, ContextBudget::CEILINGS[:boot_plus_catalog]
    assert_equal 15_000, ContextBudget::WORKING_SET_TARGET
  end

  # Can-fail proof: the bench must be observed reporting a failure,
  # driven by an injected over-budget core rather than by editing a real file.
  def test_an_over_budget_core_turns_the_report_red
    Dir.mktmpdir("plastic-bench-overbudget") do |dir|
      core = File.join(dir, "over_budget.md")
      File.write(core, "y" * 9_000)

      report = ContextBudget.run(repo: REPO, repeat: 1, core_file: core,
        fixture: ContextBudgetSharedFixture.clone("plastic-bench-overbudget-fixture"))

      refute_predicate report, :ok?, "a 9,000-byte core block must fail the 8,192 ceiling"
      assert report.failures.any? { |f| f.include?("core") },
        "the failure must name the core row; got #{report.failures.inspect}"
      assert_predicate report.row(:core), :over?
    end
  end

  def test_repeat_must_be_at_least_one
    assert_raises(ArgumentError) { ContextBudget.run(repo: REPO, repeat: 0) }
    assert_raises(ArgumentError) { ContextBudget.run(repo: REPO, repeat: -1) }
  end

  # PATH is exactly the running interpreter's directory: the hook backticks
  # scripts/read-config three times under `#!/usr/bin/env ruby`, so any other
  # PATH runs those reads under a different Ruby than the report names.
  def test_the_child_env_pins_the_interpreter_and_the_home
    env = ContextBudget.child_env(fixture)

    assert_equal File.dirname(RbConfig.ruby), env["PATH"]
    assert_nil env["RUBYOPT"]
    assert_equal fixture.home, env["HOME"]
    assert_equal fixture.plastic_home, env["PLASTIC_HOME"]
    refute_nil env["CLAUDE_CODE_SESSION_ID"]
  end

  class FakeStatus
    def initialize(ok) = @ok = ok
    def success? = @ok
    def exitstatus = @ok ? 0 : 1
  end

  # A repo carrying a hook-session-start file, to exercise the injectable
  # runner below without this repo's own tree, which ships none.
  def repo_with_hook
    dir = Dir.mktmpdir("plastic-bench-hook-repo")
    Minitest.after_run { FileUtils.remove_entry(dir) }
    FileUtils.mkdir_p(File.join(dir, "scripts"))
    FileUtils.touch(File.join(dir, "scripts", "hook-session-start"))
    dir
  end

  def test_a_repo_with_no_session_start_hook_boots_empty_with_no_runner_call
    called = false
    runner = ->(*) { called = true }

    context, ms = ContextBudget.boot(fixture: fixture, repo: REPO, runner: runner)

    assert_equal "", context
    assert_in_delta(0.0, ms)
    refute called, "a repo without the hook must not spawn anything, injected or not"
  end

  def test_the_boot_runner_is_injectable
    seen = nil
    runner = lambda do |env, *cmd, **opts|
      seen = { env: env, cmd: cmd, opts: opts }
      payload = { "hookSpecificOutput" => { "additionalContext" => "injected" } }
      [JSON.generate(payload), "", FakeStatus.new(true)]
    end

    context, ms = ContextBudget.boot(fixture: fixture, repo: repo_with_hook, runner: runner)

    assert_equal "injected", context
    assert_operator ms, :>=, 0
    assert_equal RbConfig.ruby, seen[:cmd].first
    assert_equal fixture.project_dir, seen[:opts][:chdir]
  end

  def test_a_failing_boot_is_never_scored_as_a_pass
    runner = ->(_env, *_cmd, **_opts) { ["", "boom", FakeStatus.new(false)] }

    assert_raises(RuntimeError) { ContextBudget.boot(fixture: fixture, repo: repo_with_hook, runner: runner) }
  end

  # D10: the bench is a maintainer tool over repo fixtures and is never installed
  # into ~/.plastic. Kept deliberate rather than forgotten.
  def test_the_bench_is_not_registered_for_install
    core_lib = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))

    refute_includes core_lib, "context_budget",
      "the bench is a maintainer tool; registering it would install it into ~/.plastic"

    requiring = Dir.glob(File.join(REPO, "scripts", "**", "*")).select do |path|
      File.file?(path) && File.read(path).include?("context_budget")
    end

    assert_empty requiring,
      "no shipped scripts/* file may require the bench lib: #{requiring.inspect}"
  end

  def test_the_docs_name_the_bench_and_its_ceilings
    internals = File.read(File.join(REPO, "docs", "internals.md"))

    assert_includes internals, "bin/plastic-bench"
    ["8,192", "15,000", "17,500"].each do |number|
      assert_includes internals, number, "docs/internals.md must state the #{number} ceiling"
    end
  end
end

class ContextBudgetCliTest < Minitest::Test
  REPO = ContextBudgetSharedFixture::REPO
  BENCH = File.join(REPO, "bin", "plastic-bench")

  # Only the ceiling-crossed case below still spawns the real executable: it
  # is the one proof that bin/plastic-bench itself, not just the class behind
  # it, exits non-zero over a shell caller's own process boundary. Every other
  # argument case is ContextBudget::CLI's own behavior and runs in-process.
  def self.live_crossed_run
    @live_crossed_run ||= Dir.mktmpdir("plastic-bench-cli-red") do |dir|
      core = File.join(dir, "over_budget.md")
      File.write(core, "y" * 9_000)
      ChildProcess.capture3(RbConfig.ruby, BENCH, "--repeat", "1", "--core-file", core)
    end
  end

  # Reuses the one install every other read-only case in this file shares:
  # this case never swaps a core file, so there is nothing to corrupt.
  def self.live_tree_run
    @live_tree_run ||= cli_run(["--repeat", "1"], fixture: ContextBudgetSharedFixture.fixture)
  end

  def self.cli_run(argv, fixture: nil)
    out = StringIO.new
    err = StringIO.new
    io = ContextBudget::CLI::IO.new(out: out, err: err, default_repo: REPO)
    status = ContextBudget::CLI.run(argv, io, fixture:)
    [out.string, err.string, status]
  end

  def test_the_bench_is_executable
    assert File.executable?(BENCH), "bin/plastic-bench must be executable"
  end

  def test_the_cli_exits_zero_on_the_live_tree
    out, err, status = self.class.live_tree_run

    assert_equal 0, status, "bench failed: #{err}#{out}"
    assert_includes out, "core block"
  end

  def test_the_cli_prints_the_interpreter_it_ran_under
    out, = self.class.live_tree_run

    assert_includes out, RUBY_VERSION
    assert_includes out, RbConfig.ruby
  end

  def test_the_cli_exits_non_zero_when_a_ceiling_is_crossed
    out, _err, status = self.class.live_crossed_run

    assert_equal 1, status.exitstatus, "a crossed ceiling must exit non-zero"
    assert_includes out, "core block"
  end

  def test_the_cli_rejects_a_bad_repeat_count
    out, err, status = self.class.cli_run(["--repeat", "0"])

    assert_equal 2, status
    assert_match(/usage/i, "#{out}#{err}")
  end

  def test_the_cli_has_a_help
    out, _err, status = self.class.cli_run(["--help"])

    assert_equal 0, status
    assert_match(/usage/i, out)
  end
end
