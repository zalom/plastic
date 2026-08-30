# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "yaml"

require_relative "../bin/lib/context_budget"

# Intent 313: the context budget bench. Intent 296 ruled two numbers (the core
# block under 8,192 bytes, the whole per-boot doctrine read under 15,000) and
# nothing measured either one. These tests pin what the bench measures, that it
# measures it hermetically, and that a crossed ceiling turns the suite red.
#
# Hermetic and DI throughout: every fixture is a Dir.mktmpdir with its own HOME
# and PLASTIC_HOME, the boot subprocess's env is injectable and asserted, and no
# case reads the real ~/.plastic or ~/.claude.

# The estimator, the skill split, the catalog and the median: pure functions over
# strings and a synthetic two-skill tree.
class ContextBudgetMeasureTest < Minitest::Test
  # skill_lint.rb:104 is `(body.split(/\s+/).reject(&:empty?).length * 1.3).round`.
  # If this drifts, the bench and skill-lint report different token counts for the
  # same file, which is the one thing D1 exists to prevent.
  def test_measure_uses_skill_lints_arithmetic
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

  def test_measure_counts_lines
    assert_equal 3, ContextBudget.measure("a\nb\nc\n").lines
  end

  # skill_lint.rb:82-90: content.split("---", 3), parts[1] frontmatter, parts[2] body.
  def test_split_skill_matches_skill_lints_split
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
    # A folded (multi-line) description: the shape a naive line regex truncates.
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

  def test_skill_catalog_keeps_a_folded_description_whole
    Dir.mktmpdir("plastic-bench-folded") do |dir|
      build_skill_tree(dir)
      beta = File.join(dir, "skills", "beta", "SKILL.md")
      frontmatter, = ContextBudget.split_skill(File.read(beta))
      description = (YAML.safe_load(frontmatter) || {})["description"].to_s

      assert_includes description, "second half",
        "a folded description must be parsed whole, not truncated at the first line"
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
  REPO = File.expand_path("../../", __FILE__)

  def with_fixture
    Dir.mktmpdir("plastic-bench-fixture") do |dir|
      yield ContextBudget::Fixture.build(dir: dir, repo: REPO)
    end
  end

  def test_build_runs_the_real_installer
    with_fixture do |fixture|
      assert File.file?(File.join(fixture.plastic_home, "VERSION")),
        "the fixture must carry an installed VERSION"
      refute_empty Dir.glob(File.join(fixture.home, ".claude", "hooks", "*")),
        "the fixture must carry installed Claude hook launchers, or the boot measures a degraded install"
    end
  end

  def test_build_copies_the_repos_own_core_block
    with_fixture do |fixture|
      assert_equal File.size(File.join(REPO, "PLASTIC.md")),
                   File.size(File.join(fixture.plastic_home, "PLASTIC.md")),
                   "the fixture must measure the repo's core block, never a stale one"
    end
  end

  # On macOS Dir.pwd resolves /var to /private/var; without realpath the hook's
  # cwd.start_with?(project_path) test silently misses and the project banner
  # disappears from the measured context.
  def test_build_realpaths_the_project_directory
    with_fixture do |fixture|
      assert_equal File.realpath(fixture.project_dir), fixture.project_dir
      assert_equal File.realpath(fixture.home), fixture.home
    end
  end

  def test_build_stays_inside_the_given_directory
    with_fixture do |fixture|
      env = ContextBudget.child_env(fixture)

      %w[HOME PLASTIC_HOME PLASTIC_TMP].each do |key|
        assert env[key].start_with?(fixture.home),
          "#{key} (#{env[key]}) must live inside the fixture, never in the real home"
      end
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

# One live report, memoized: install once, boot three times, assert everything
# about the result. Three repeats keep the suite cheap; the CLI defaults to five.
class ContextBudgetBootTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  def self.report
    @report ||= ContextBudget.run(repo: REPO, repeat: 3)
  end

  def report
    self.class.report
  end

  def test_the_fixture_boots_healthy
    assert_match(/doctor --core run: success\z/, report.context.lines.first.strip,
      "a degraded fixture measures a boot no real session sees")
  end

  def test_the_boot_carries_the_core_block
    assert_includes report.context, "# Plastic: Conventions"
  end

  def test_the_boot_renders_the_project_banner_and_its_active_intent
    assert_includes report.context, "Project: "
    assert_includes report.context, "Active intents:"
  end

  # The rendered age must be a constant, not a function of the calendar, or the
  # byte count drifts by a digit every ten days.
  def test_the_stale_line_age_does_not_drift_with_the_calendar
    assert_includes report.context, "(30 days)"
  end

  # The two QMD status lines the hook can emit (hook-session-start's qmd block).
  # Not the bare word "QMD", which PLASTIC.md itself uses in its own doctrine.
  def test_no_host_state_leaks_into_the_measurement
    refute_includes report.context, "Plastic collections indexed",
      "a host with qmd on PATH must not change the measured bytes"
    refute_includes report.context, "qmd-sync register --all",
      "a host without a registered qmd must not change the measured bytes either"
    refute_includes report.context, "update available",
      "a real update-check cache must not change the measured bytes"
  end

  def test_repeats_are_byte_identical
    assert_equal 3, report.samples.length
    assert_equal 0, report.byte_spread,
      "the fixture is fixed, so any byte spread across repeats means something non-deterministic leaked in"
  end

  def test_every_enforced_row_is_under_its_ceiling
    report.rows.select(&:enforced?).each do |row|
      assert_operator row.bytes, :<, row.ceiling,
        "#{row.key} is #{row.bytes} bytes against a #{row.ceiling} ceiling"
    end
    assert report.ok?, "live report must pass: #{report.failures.join('; ')}"
  end

  def test_the_working_set_is_reported_with_its_ruled_target
    row = report.row(:working_set)

    refute row.enforced?, "the working set carries no ceiling; its median term steps by a kilobyte"
    assert_equal ContextBudget::WORKING_SET_TARGET, row.target
    refute_nil row.gap, "the gap to the ruled 15,000 must be reported, not hidden"
  end

  def test_the_catalog_and_the_combined_row_are_both_present
    assert_operator report.row(:skill_catalog).bytes, :>, 0
    assert_equal report.row(:boot).bytes + report.row(:skill_catalog).bytes,
                 report.row(:boot_plus_catalog).bytes
  end

  def test_the_table_renders_a_ceiling_or_the_word_reported_for_every_row
    table = report.to_table

    report.rows.each do |row|
      assert_includes table, row.label
    end
    assert_includes table, "reported"
    assert_includes table, ContextBudget::WORKING_SET_TARGET.to_s
  end

  # Intent 242's standing complaint: a measurement that never says which
  # interpreter produced it.
  def test_the_report_names_the_interpreter
    assert_equal RUBY_VERSION, report.ruby_version
    assert_equal RbConfig.ruby, report.ruby_bin
    assert_includes report.to_table, RUBY_VERSION
  end

  def test_the_report_names_what_it_could_not_count
    assert_match(/not counted/i, report.to_table,
      "the report must state its exclusions (update notice, sweep line, qmd line)")
  end
end

class ContextBudgetCeilingTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  # The ruled numbers (intent 296) plus the one ratchet intent 313 adds. A change
  # here is a change to a ruling and must be argued, not typed.
  def test_ceilings_are_the_ruled_numbers
    assert_equal 8_192, ContextBudget::CEILINGS[:core]
    assert_equal 15_000, ContextBudget::CEILINGS[:boot]
    assert_equal 17_500, ContextBudget::CEILINGS[:boot_plus_catalog]
    assert_equal 15_000, ContextBudget::WORKING_SET_TARGET
  end

  # Can-fail proof (intent 208): the bench must be observed reporting a failure,
  # driven by an injected over-budget core rather than by editing a real file.
  def test_an_over_budget_core_turns_the_report_red
    Dir.mktmpdir("plastic-bench-overbudget") do |dir|
      core = File.join(dir, "over_budget.md")
      File.write(core, "y" * 9_000)

      report = ContextBudget.run(repo: REPO, repeat: 1, core_file: core)

      refute report.ok?, "a 9,000-byte core block must fail the 8,192 ceiling"
      assert report.failures.any? { |f| f.include?("core") },
        "the failure must name the core row; got #{report.failures.inspect}"
      assert report.row(:core).over?
    end
  end

  def test_repeat_must_be_at_least_one
    assert_raises(ArgumentError) { ContextBudget.run(repo: REPO, repeat: 0) }
    assert_raises(ArgumentError) { ContextBudget.run(repo: REPO, repeat: -1) }
  end

  # PATH is exactly the running interpreter's directory: the hook backticks
  # scripts/read-config three times under `#!/usr/bin/env ruby`, so any other
  # PATH runs those reads under a different Ruby than the report names, and a
  # host with qmd on PATH would add a QMD line to the measurement.
  def test_the_child_env_pins_the_interpreter_and_the_home
    Dir.mktmpdir("plastic-bench-env") do |dir|
      fixture = ContextBudget::Fixture.build(dir: dir, repo: REPO)
      env = ContextBudget.child_env(fixture)

      assert_equal File.dirname(RbConfig.ruby), env["PATH"]
      assert_nil env["RUBYOPT"]
      assert_equal fixture.home, env["HOME"]
      assert_equal fixture.plastic_home, env["PLASTIC_HOME"]
      refute_nil env["CLAUDE_CODE_SESSION_ID"]
    end
  end

  class FakeStatus
    def initialize(ok) = @ok = ok
    def success? = @ok
    def exitstatus = @ok ? 0 : 1
  end

  def test_the_boot_runner_is_injectable
    Dir.mktmpdir("plastic-bench-runner") do |dir|
      fixture = ContextBudget::Fixture.build(dir: dir, repo: REPO)
      seen = nil
      runner = lambda do |env, *cmd, **opts|
        seen = { env: env, cmd: cmd, opts: opts }
        payload = { "hookSpecificOutput" => { "additionalContext" => "injected" } }
        [JSON.generate(payload), "", FakeStatus.new(true)]
      end

      context, ms = ContextBudget.boot(fixture: fixture, repo: REPO, runner: runner)

      assert_equal "injected", context
      assert_operator ms, :>=, 0
      assert_equal RbConfig.ruby, seen[:cmd].first
      assert_equal fixture.project_dir, seen[:opts][:chdir]
    end
  end

  def test_a_failing_boot_is_never_scored_as_a_pass
    Dir.mktmpdir("plastic-bench-failboot") do |dir|
      fixture = ContextBudget::Fixture.build(dir: dir, repo: REPO)
      runner = ->(_env, *_cmd, **_opts) { ["", "boom", FakeStatus.new(false)] }

      assert_raises(RuntimeError) { ContextBudget.boot(fixture: fixture, repo: REPO, runner: runner) }
    end
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

  def test_the_architecture_doc_no_longer_states_the_stale_ceilings
    architecture = File.read(File.join(REPO, "docs", "architecture.md"))

    refute_includes architecture, "5,000 estimated tokens",
      "the live token ceiling is 1,600 (intent 305), not skill-lint's 5,000"
    refute_includes architecture, "8 `references/*.md`",
      "the ruled chapter set is 6 (intent 304)"
    assert_includes architecture, "bin/plastic-bench"
  end
end

class ContextBudgetCliTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)
  BENCH = File.join(REPO, "bin", "plastic-bench")

  def self.live_run
    @live_run ||= Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, BENCH, "--repeat", "1")
  end

  def test_the_bench_is_executable
    assert File.executable?(BENCH), "bin/plastic-bench must be executable"
  end

  def test_the_cli_exits_zero_on_the_live_tree
    out, err, status = self.class.live_run

    assert_equal 0, status.exitstatus, "bench failed: #{err}#{out}"
    assert_includes out, "core block"
  end

  def test_the_cli_prints_the_interpreter_it_ran_under
    out, _err, _status = self.class.live_run

    assert_includes out, RUBY_VERSION
    assert_includes out, RbConfig.ruby
  end

  def test_the_cli_exits_non_zero_when_a_ceiling_is_crossed
    Dir.mktmpdir("plastic-bench-cli-red") do |dir|
      core = File.join(dir, "over_budget.md")
      File.write(core, "y" * 9_000)

      out, _err, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, BENCH,
                                         "--repeat", "1", "--core-file", core)

      assert_equal 1, status.exitstatus, "a crossed ceiling must exit non-zero"
      assert_includes out, "core block"
    end
  end

  def test_the_cli_rejects_a_bad_repeat_count
    out, err, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, BENCH, "--repeat", "0")

    assert_equal 2, status.exitstatus
    assert_match(/usage/i, "#{out}#{err}")
  end

  def test_the_cli_has_a_help
    out, _err, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, BENCH, "--help")

    assert_equal 0, status.exitstatus
    assert_match(/usage/i, out)
  end
end
