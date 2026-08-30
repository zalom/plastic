# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "stringio"

require_relative "../scripts/rollback"
require_relative "../scripts/lib/installer_core"
require_relative "../scripts/lib/release_guard"

# Intent 310, cut-inventory risk R2: rollback across the major. Hermetic under Dir.mktmpdir
# with injected homes and agent dirs, no ENV seam. Four proofs: the rollback verb derives a
# downgrade and targets every installed harness; a newer package that prunes a skill is undone
# by reinstalling the older one (two fake package roots); the real 1.14.1 installer, from the
# v1.14.1 tag, registers a clean settings.json after 2.0's own registrations are stripped (the
# rollback prepare step), and its doctor's hook checks pass; and the real 1.14.1 doctor reads
# a store the alpha wrote with every named check passing, except the one recorded wart (a
# backfilled_complete exclusion row, unknown to 1.14.1's parser, warns).
class RollbackMajorTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  class RecordingRollback < Rollback
    def switch_calls
      @switch_calls ||= []
    end

    def switch_to(target, current)
      prepare_switch(target, current)
      switch_calls << { target: target, current: current, action: action_for(target, current), flags: harness_flags }
      0
    end
  end

  def setup
    @home = Dir.mktmpdir("rollback-major")
    # The agent dir sits under the tmp home: the 1.14.1 installer (run as a child with
    # HOME pointed here) writes hook commands under $HOME/.claude/hooks.
    @claude_dir = File.join(@home, ".claude")
    FileUtils.mkdir_p(@claude_dir)
    @codex_dir = Dir.mktmpdir("rollback-agents")
    @codex_home = Dir.mktmpdir("rollback-codex-home")
    @agents = [
      { key: "claude", name: "Claude Code", dir: @claude_dir, flag: "--claude" },
      { key: "codex", name: "Codex CLI", dir: @codex_dir, home_dir: @codex_home, flag: "--codex" },
    ]
  end

  def teardown
    [@home, @codex_dir, @codex_home, *(@extra || [])].each { |d| FileUtils.rm_rf(d) if d }
  end

  def extra_dir(label)
    (@extra ||= []) << Dir.mktmpdir(label)
    @extra.last
  end

  def rollback
    RecordingRollback.new(package_root: ".", plastic_home: @home, agents: @agents, version: "x")
  end

  def record_agent(dir, version)
    FileUtils.mkdir_p(File.join(dir, "plastic"))
    File.write(File.join(dir, "plastic", "VERSION"), "#{version}\n")
  end

  # --- (a) the rollback verb across the major ---------------------------------------------

  def test_rollback_from_the_alpha_to_1_14_1_is_a_downgrade_for_every_installed_harness
    v = rollback
    v.ledger_append("1.14.1", "install", harness: "claude")
    v.ledger_append("2.0.0-alpha.1", "update", harness: "claude")
    File.write(File.join(@home, "VERSION"), "2.0.0-alpha.1\n")
    record_agent(@claude_dir, "2.0.0-alpha.1")
    record_agent(@codex_dir, "2.0.0-alpha.1")

    assert_equal ["1.14.1", "2.0.0-alpha.1"], v.version_timeline(v.ledger_read)
    assert_equal "downgrade", v.action_for("1.14.1", "2.0.0-alpha.1")
    assert_equal "update", v.action_for("2.0.0-alpha.1", "1.14.1")

    capture_io { assert_equal 0, v.cli(["--version", "1.14.1"]) }
    assert_equal [{ target: "1.14.1", current: "2.0.0-alpha.1", action: "downgrade", flags: %w[--claude --codex] }],
                 v.switch_calls
  end

  def test_rollback_defaults_to_claude_when_no_harness_record_exists_and_never_switches_implicitly
    v = rollback
    v.ledger_append("1.14.1", "install", harness: "claude")
    v.ledger_append("2.0.0-alpha.1", "update", harness: "claude")
    File.write(File.join(@home, "VERSION"), "2.0.0-alpha.1\n")

    assert_equal %w[--claude], v.harness_flags
    capture_io { assert_equal 0, v.cli([]) }
    capture_io { assert_equal 1, v.cli(["--downgrade"]) }
    assert_empty v.switch_calls
  end

  # Intent 312: prepare_switch reports the CLAUDE.md path only when it actually stripped
  # something, so the exact-list assertion above cannot be satisfied by a phantom entry.
  def test_prepare_switch_reports_no_claude_md_when_no_compact_section_is_present
    settings = File.join(@claude_dir, "settings.json")
    record_agent(@claude_dir, "2.0.0-alpha.1")
    core = InstallerCore.new(package_root: REPO, plastic_home: @home, agents: @agents, version: "2.0.0-alpha.1")
    File.write(settings, JSON.pretty_generate("hooks" => {}))
    capture_io { core.merge_claude_hooks(settings) }

    v = rollback
    stripped = nil
    capture_io { stripped = v.prepare_switch("1.14.1", "2.0.0-alpha.1") }

    assert_equal [settings], stripped
  end

  # --- (b) the rollback prepare step strips 2.0's own registrations -------------------------

  def test_prepare_switch_strips_current_registrations_on_a_downgrade_only
    settings = File.join(@claude_dir, "settings.json")
    hooks_json = File.join(@codex_home, "hooks.json")
    record_agent(@claude_dir, "2.0.0-alpha.1")
    record_agent(@codex_dir, "2.0.0-alpha.1")
    core = InstallerCore.new(package_root: REPO, plastic_home: @home, agents: @agents, version: "2.0.0-alpha.1")
    File.write(settings, JSON.pretty_generate("hooks" => { "SessionStart" => [{ "matcher" => "", "hooks" => [
      { "type" => "command", "command" => "~/bin/my-own-hook" },
    ] }] }))
    capture_io { core.merge_claude_hooks(settings) }
    File.write(hooks_json, "{}")
    capture_io { core.merge_codex_hooks(hooks_json) }
    claude_md = File.join(@claude_dir, "CLAUDE.md")
    core.inject_claude_compact_md(claude_md)
    assert_match(/plastic-close/, File.read(settings), "fixture: 2.0 registered its hooks")
    assert_match(/close/, File.read(hooks_json), "fixture: 2.0 registered Codex hooks")
    assert_includes File.read(claude_md), InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX,
                    "fixture: 2.0 installed the compact-instructions block"

    v = rollback
    capture_io { assert_equal [], v.prepare_switch("2.0.0-alpha.1", "1.14.1"), "an upgrade strips nothing" }
    assert_match(/plastic-close/, File.read(settings))

    stripped = nil
    capture_io { stripped = v.prepare_switch("1.14.1", "2.0.0-alpha.1") }
    assert_equal [settings, hooks_json, claude_md].sort, stripped.sort
    refute_includes File.read(claude_md), InstallerCore::CLAUDE_SECTION_BEGIN_PREFIX,
                    "intent 312: an older package cannot see the compact section, so the downgrade strips it"
    after = File.read(settings)
    refute_match(/plastic-/, after, "every Plastic registration is gone")
    assert_match(%r{~/bin/my-own-hook}, after, "the user's own hook survives")
    refute(File.exist?(hooks_json) && File.read(hooks_json).include?("codex-hook"),
           "the Codex registrations are gone (an emptied hooks.json may be removed outright)")
  end

  # --- (c) prune-and-restore round trip across two package roots ---------------------------

  def fake_package_root(label, skills:, version:)
    root = extra_dir("pkg-#{label}")
    File.write(File.join(root, "package.json"), JSON.generate("name" => "@zalom/plastic", "version" => version))
    File.write(File.join(root, "PLASTIC.md"), "# Plastic #{version}\n")
    FileUtils.mkdir_p(File.join(root, "scripts", "lib"))
    File.write(File.join(root, "scripts", "doctor.rb"), "puts 'stub'\n")
    FileUtils.mkdir_p(File.join(root, "hooks"))
    File.write(File.join(root, "hooks", "session-start"), "#!/bin/bash\nexit 0\n")
    FileUtils.mkdir_p(File.join(root, "templates"))
    FileUtils.mkdir_p(File.join(root, "agents"))
    skills.each do |name|
      FileUtils.mkdir_p(File.join(root, "skills", name))
      File.write(File.join(root, "skills", name, "SKILL.md"), "---\nname: plastic-#{name}\ndescription: #{name}\n---\n# #{name}\n")
    end
    root
  end

  def install(root, version, reinstall: false)
    core = InstallerCore.new(package_root: root, plastic_home: @home, agents: @agents, version: version)
    capture_io do
      core.distribute(reinstall ? :update : :install)
      result = core.install_for_agent("claude", true, argv: [], input: StringIO.new("\n"), reinstall: reinstall)
      assert result[:success], result.inspect
    end
    core
  end

  def test_a_skill_pruned_by_the_newer_package_is_restored_by_reinstalling_the_older_one
    v1 = fake_package_root("v1", skills: %w[alpha bravo], version: "1.14.1")
    v2 = fake_package_root("v2", skills: %w[alpha], version: "2.0.0-alpha.1")
    bravo = File.join(@claude_dir, "skills", "plastic-bravo", "SKILL.md")

    install(v1, "1.14.1")
    assert File.exist?(bravo), "v1 installs bravo"

    install(v2, "2.0.0-alpha.1", reinstall: true)
    refute File.exist?(bravo), "the 2.0 install prunes the skill it no longer ships"
    assert_equal "2.0.0-alpha.1", File.read(File.join(@home, "VERSION")).strip

    install(v1, "1.14.1", reinstall: true)
    assert File.exist?(bravo), "reinstalling 1.14.1 restores the pruned skill"
    assert_equal "1.14.1", File.read(File.join(@home, "VERSION")).strip
    manifest = JSON.parse(File.read(File.join(@claude_dir, "plastic", "manifest.json")))
    assert manifest["files"].keys.any? { |k| k.end_with?("plastic-bravo/SKILL.md") }, "the manifest lists the restored skill"
  end

  # --- (d) the real 1.14.1 installer and doctor, from the tag ---------------------------------

  def extract_1_14_1
    return @old if @old

    dir = extra_dir("plastic-1-14-1")
    out, err, status = Open3.capture3("git", "-C", REPO, "archive", "v1.14.1")
    skip "tag v1.14.1 is not in this clone: #{err.strip}" unless status.success?
    Open3.capture3("tar", "-x", "-C", dir, stdin_data: out)
    @old = dir
  end

  # Runs a Ruby snippet against the 1.14.1 tree in a child process (its libs must not load
  # into this suite) and returns the JSON it prints.
  def run_1_14_1(old, script)
    out, err, status = Open3.capture3({ "RUBYOPT" => nil, "HOME" => @home },
                                      RbConfig.ruby, "-e", script, chdir: old)
    assert status.success?, "the 1.14.1 child failed: #{err}\n#{out}"
    JSON.parse(out[out.rindex("\n{")&.+(1) || out.index("{")..])
  end

  def test_rolling_back_to_the_real_1_14_1_installer_leaves_no_orphaned_hook_registration
    old = extract_1_14_1
    settings = File.join(@claude_dir, "settings.json")
    record_agent(@claude_dir, "2.0.0-alpha.1")

    # 1. The real 2.0 install (this repo) over the tmp home and agent dir.
    core = InstallerCore.new(package_root: REPO, plastic_home: @home, agents: @agents, version: "2.0.0-alpha.1")
    capture_io do
      core.distribute(:install)
      assert core.install_for_agent("claude", true, argv: [], input: StringIO.new("\n"))[:success]
    end
    assert File.exist?(File.join(@claude_dir, "hooks", "plastic-close"))

    # 2. The rollback prepare step (2.0 code), then the real 1.14.1 installer (child process).
    capture_io { rollback.prepare_switch("1.14.1", "2.0.0-alpha.1") }
    report = run_1_14_1(old, <<~RUBY)
      require "json"
      require "stringio"
      require "./scripts/lib/installer_core"
      require "./scripts/lib/doctor_core"
      require "./scripts/doctor"
      agents = [{ key: "claude", name: "Claude Code", dir: #{@claude_dir.inspect}, flag: "--claude" }]
      core = InstallerCore.new(package_root: ".", plastic_home: #{@home.inspect}, agents: agents, version: "1.14.1")
      $stdout = StringIO.new
      core.distribute(:update)
      result = core.install_for_agent("claude", true, argv: [], input: StringIO.new("\\n"), reinstall: true)
      doctor = Doctor.new(plastic_home: #{@home.inspect}, agents: { "claude" => { name: "Claude Code", dir: #{@claude_dir.inspect} } })
      checks = doctor.check_agent_registration("claude")
      $stdout = STDOUT
      puts JSON.generate("install" => result, "checks" => checks)
    RUBY

    assert report["install"]["success"], report["install"].inspect
    assert_equal "1.14.1", File.read(File.join(@home, "VERSION")).strip
    launchers = Dir.children(File.join(@claude_dir, "hooks"))
    commands = JSON.parse(File.read(settings))["hooks"].values.flatten.flat_map { |g| g["hooks"].map { |h| h["command"] } }
    dangling = commands.map { |c| File.basename(c) }.reject { |b| launchers.include?(b) }
    assert_empty dangling, "every registered command must name a launcher 1.14.1 installed"
    refute File.exist?(File.join(@claude_dir, "hooks", "plastic-close")), "1.14.1's manifest diff removed 2.0's launcher"
    %w[hooks_entries_owned hooks_match_registry hooks_exist hooks_no_orphans].each do |name|
      c = report["checks"].find { |x| x["name"] == name }
      refute_nil c, "1.14.1 doctor emits #{name}"
      assert_equal "pass", c["status"], "#{name}: #{c["message"]} #{c["details"].inspect}"
    end
  end

  def write_2_0_store(home, exclusion_row: nil)
    store = File.join(home, "store")
    FileUtils.rm_rf(store)
    intent = File.join(store, "5--demo")
    FileUtils.mkdir_p(File.join(intent, "actions"))
    File.write(File.join(intent, "5--demo.md"), <<~MD)
      ---
      id: "5"
      intent: "Demo intent"
      sources: []
      chain: []
      created: 2026-08-30
      author: human
      tags: []
      ---

      ## Intent
      Demo

      ## Context

      ## Outcome
      (placeholder)

      ## Insights

      ## Links
      <!-- No sources or chain; this intent has no graph edges to project. -->
    MD
    File.write(File.join(intent, "spec.md"), "# Spec: Demo intent\n<!-- backfilled from the record by end-intent on 2026-08-30T00:00:00Z -->\n\n## Problem\nDemo\n")
    File.write(File.join(intent, "savepoint.md"), "2026-08-30T00:00:00Z  What  5--demo.md\n2026-08-30T00:00:01Z  Exec  backfilled spec.md\n")
    day = File.join(store, ".sessions", "20260830")
    FileUtils.mkdir_p(day)
    File.write(File.join(day, "20260830.md"), "---\nid: \"20260830\"\nintent: \"Session ledger 20260830\"\nmode: direct\n---\n")
    File.write(File.join(day, "checklist.md"), "# Checklist: session ledger 20260830\n\n- [x] [abcd1234] [global] did a thing\n")
    tmp = File.join(store, ".tmp", "abcd1234")
    FileUtils.mkdir_p(tmp)
    File.write(File.join(store, ".tmp", ".gitignore"), "*\n")
    File.write(File.join(tmp, "current"), "20260830\n")
    File.write(File.join(tmp, "heartbeat"), "2026-08-30T00:00:00Z\n")
    File.write(File.join(home, "INDEX.md"), "# Index\n\n## Active\n- [5 — Demo intent](store/5--demo/5--demo.md) — demo\n\n## Future\n\n## Clusters\n\n## Abandoned\n\n## Completed\n")
    exclusions = File.join(home, "doctor-exclusions")
    exclusion_row ? File.write(exclusions, "#{exclusion_row}\n") : FileUtils.rm_f(exclusions)
    store
  end

  def doctor_1_14_1_store_checks(old, home)
    run_1_14_1(old, <<~RUBY)
      require "json"
      require "./scripts/doctor"
      doctor = Doctor.new(plastic_home: #{home.inspect})
      checks = doctor.check_global_store + doctor.check_conventions(scopes: ["global"]) + doctor.check_done_signals(scopes: ["global"])
      puts JSON.generate("checks" => checks)
    RUBY
  end

  def test_the_1_14_1_doctor_reads_a_store_the_alpha_wrote_with_every_named_check_passing
    old = extract_1_14_1
    home = extra_dir("plastic-home-1-14")
    write_2_0_store(home)
    checks = doctor_1_14_1_store_checks(old, home)["checks"]

    by_name = checks.to_h { |c| [c["name"], c] }
    %w[orphaned_intents ghost_references index_sections savepoint_operational signals_agree].each do |name|
      refute_nil by_name[name], "1.14.1 emits #{name}"
      assert_equal "pass", by_name[name]["status"], "#{name}: #{by_name[name]["message"]} #{by_name[name]["details"].inspect}"
    end
    conventions = checks.select { |c| c["category"] == "conventions" }
    refute_empty conventions
    assert(conventions.all? { |c| c["status"] == "pass" }, conventions.map { |c| [c["name"], c["status"], c["details"]] }.inspect)
    dotted = checks.flat_map { |c| Array(c["details"]) + [c["message"]] }.select { |d| d.to_s.include?(".sessions") || d.to_s.include?(".tmp") }
    assert_empty dotted, "no 1.14.1 check names the dot-prefixed directories"
  end

  def test_the_1_14_1_doctor_warns_on_a_backfilled_complete_exclusion_row_the_recorded_wart
    old = extract_1_14_1
    home = extra_dir("plastic-home-1-14-wart")
    write_2_0_store(home, exclusion_row: "backfilled_complete 5")
    checks = doctor_1_14_1_store_checks(old, home)["checks"]
    c = checks.find { |x| x["name"] == "savepoint_operational" }

    assert_equal "warn", c["status"], c.inspect
    assert_match(/backfilled_complete/, c["details"].join(" "), "the unknown rule is named")
  end

  # --- (e) the release guard on the real version files ------------------------------------------

  def test_release_guard_accepts_the_repo_version_files_for_a_prerelease_cut
    r = ReleaseGuard.check(package_json: File.join(REPO, "package.json"),
                           plugin_json: File.join(REPO, ".claude-plugin", "plugin.json"),
                           marketplace_json: File.join(REPO, ".claude-plugin", "marketplace.json"),
                           stable: false)
    assert r.ok?, r.inspect
    assert_empty r.mismatches
  end
end
