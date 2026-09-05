# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"

require_relative "../scripts/doctor"
require_relative "support/hook_replay"

# Coverage for intent 331e (actions/ACTION_1.md, rows E1-E24): the doctor
# `display` category. Four checks: `display_hook_registered` (boot-path,
# scripts/lib/doctor_core.rb, --core-scoped), `display_hook_paints`,
# `display_not_defeated`, and `display_surfaces_documented` (all three in
# scripts/doctor.rb, full-run only).
#
# Hermetic throughout: every fixture lives in a Dir.mktmpdir, every replay
# passes PLASTIC_TMP via HookReplay and an explicit PLASTIC_HOME, no eval, no
# reliance on ENV (no_color is DI'd), no reads of the real ~/.plastic or
# ~/.claude — display_hook_registered's own E18 test exists specifically to
# prove that.
class DoctorDisplayTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # --- fixture helpers ------------------------------------------------------

  def agents_for(claude_dir)
    {
      "claude" => { name: "Claude Code", dir: claude_dir },
      "codex"  => { name: "Codex CLI", dir: File.join(claude_dir, "..", "codex-not-installed") },
      "hermes" => { name: "Hermes", dir: File.join(claude_dir, "..", "hermes-not-installed") },
    }
  end

  def message_display_hooks(command)
    { "MessageDisplay" => [{ "matcher" => "", "hooks" => [{ "type" => "command", "command" => command }] }] }
  end

  def write_settings(claude_dir, hooks:, extra: {})
    FileUtils.mkdir_p(claude_dir)
    File.write(File.join(claude_dir, "settings.json"), JSON.generate({ "hooks" => hooks }.merge(extra)))
  end

  def write_launcher(claude_dir, executable: true, content: "#!/bin/bash\nexit 0\n")
    path = File.join(claude_dir, "hooks", "plastic-message-display")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.chmod(executable ? 0o755 : 0o644, path)
    path
  end

  # A launcher good enough for the paint check: always emits a
  # hookSpecificOutput envelope, colored or plain depending on `color`.
  def write_working_launcher(claude_dir, color:)
    display = color ? '\e[1mPainted\e[0m' : "Plain text, never colored"
    script = <<~RUBY
      #!/usr/bin/env ruby
      require "json"
      $stdin.read
      puts JSON.generate("hookSpecificOutput" => { "hookEventName" => "MessageDisplay",
        "displayContent" => "#{display}" })
    RUBY
    write_launcher(claude_dir, executable: true, content: script)
  end

  def write_fixture(home)
    FileUtils.mkdir_p(File.join(home, "templates"))
    File.write(File.join(home, "templates", "display-fixture.md"),
      "<!-- test fixture -->\n\n## ▶ demo\n\nplain body\n")
  end

  # =========================================================================
  # check_display_registration (scripts/lib/doctor_core.rb, --core scope)
  # =========================================================================

  def test_registered_fails_without_hook_line # E1
    Dir.mktmpdir("plastic-display-e1") do |dir|
      claude_dir = File.join(dir, "claude")
      write_launcher(claude_dir)
      write_settings(claude_dir, hooks: {})

      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("claude").first

      assert_equal "display", check[:category]
      assert_equal "display_hook_registered", check[:name]
      assert_equal "fail", check[:status]
      assert check[:fixable]
    end
  end

  def test_registered_requires_plastic_command # E2
    Dir.mktmpdir("plastic-display-e2") do |dir|
      claude_dir = File.join(dir, "claude")
      write_launcher(claude_dir)
      write_settings(claude_dir, hooks: message_display_hooks("/usr/bin/some-foreign-tool"))

      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("claude").first

      assert_equal "fail", check[:status]
    end
  end

  def test_registered_fails_when_settings_unreadable # E14
    Dir.mktmpdir("plastic-display-e14") do |dir|
      claude_dir = File.join(dir, "claude")
      write_launcher(claude_dir)
      # settings.json intentionally never written

      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("claude").first

      assert_equal "fail", check[:status]
    end
  end

  def test_registered_fails_on_empty_hooks_array # E15
    Dir.mktmpdir("plastic-display-e15") do |dir|
      claude_dir = File.join(dir, "claude")
      write_launcher(claude_dir)
      write_settings(claude_dir, hooks: { "MessageDisplay" => [] })

      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("claude").first

      assert_equal "fail", check[:status]
    end
  end

  def test_registered_fails_when_launcher_file_missing # E16
    Dir.mktmpdir("plastic-display-e16") do |dir|
      claude_dir = File.join(dir, "claude")
      launcher_path = File.join(claude_dir, "hooks", "plastic-message-display")
      write_settings(claude_dir, hooks: message_display_hooks(launcher_path))
      # the launcher file itself is never written

      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("claude").first

      assert_equal "fail", check[:status]
    end
  end

  def test_registered_fails_when_launcher_not_executable # E17
    Dir.mktmpdir("plastic-display-e17") do |dir|
      claude_dir = File.join(dir, "claude")
      launcher_path = write_launcher(claude_dir, executable: false)
      write_settings(claude_dir, hooks: message_display_hooks(launcher_path))

      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("claude").first

      assert_equal "fail", check[:status]
    end
  end

  def test_registered_reads_only_the_injected_agent_dir # E18
    Dir.mktmpdir("plastic-display-e18") do |dir|
      claude_dir = File.join(dir, "claude")
      FileUtils.mkdir_p(claude_dir)
      # No settings.json, no launcher: on THIS machine the real ~/.claude has
      # MessageDisplay registered (established fact) — a check that secretly
      # fell back to Dir.home instead of the injected agent_dir would report
      # pass here. Only reading the injected dir reports fail.

      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("claude").first

      assert_equal "fail", check[:status]
    end
  end

  def test_registered_passes_on_a_correctly_registered_install
    Dir.mktmpdir("plastic-display-e-pass") do |dir|
      claude_dir = File.join(dir, "claude")
      launcher_path = write_launcher(claude_dir)
      write_settings(claude_dir, hooks: message_display_hooks(launcher_path))

      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("claude").first

      assert_equal "pass", check[:status]
    end
  end

  def test_registered_skips_non_claude_harness
    Dir.mktmpdir("plastic-display-e-codex") do |dir|
      claude_dir = File.join(dir, "claude")
      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_registration("codex").first

      assert_equal "pass", check[:status]
      assert_includes check[:message], "plain by contract"
    end
  end

  # =========================================================================
  # check_display_paints (scripts/doctor.rb, full run only)
  # =========================================================================

  def test_paints_writes_only_under_injected_tmp # E3
    Dir.mktmpdir("plastic-display-e3-parent") do |parent|
      Dir.mktmpdir("plastic-display-e3-home") do |home|
        claude_dir = File.join(home, "..", "claude-e3")
        write_fixture(home)
        write_working_launcher(claude_dir, color: true)

        factory_calls = []
        d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
        d.check_display_paints(
          "claude", no_color: nil,
          tmp_dir_factory: lambda {
            tmp = Dir.mktmpdir("plastic-doctor-display", parent)
            factory_calls << tmp
            tmp
          }
        )

        assert_equal 1, factory_calls.size
        refute Dir.exist?(factory_calls.first), "the check must clean up its own tmp dir"
        assert_empty Dir.children(parent), "nothing besides the injected tmp dir may appear under its parent"
      end
    end
  end

  def test_paints_fails_without_sgr # E4
    Dir.mktmpdir("plastic-display-e4") do |dir|
      home = File.join(dir, "home")
      claude_dir = File.join(dir, "claude")
      FileUtils.mkdir_p([home, claude_dir])
      write_fixture(home)
      write_working_launcher(claude_dir, color: false)

      d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
      check = d.check_display_paints("claude", no_color: nil).first

      assert_equal "display_hook_paints", check[:name]
      assert_equal "fail", check[:status]
    end
  end

  def test_paints_passes_when_defeated_and_names_the_defeater # E19
    Dir.mktmpdir("plastic-display-e19") do |dir|
      home = File.join(dir, "home")
      claude_dir = File.join(dir, "claude")
      FileUtils.mkdir_p([home, claude_dir])
      write_fixture(home)
      write_working_launcher(claude_dir, color: false)

      d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
      check = d.check_display_paints("claude", no_color: "1").first

      assert_equal "pass", check[:status]
      assert_includes check[:message], "NO_COLOR"
    end
  end

  def test_paints_replays_the_installed_launcher # E20
    source = File.read(File.join(ROOT, "scripts", "doctor.rb"))
    body = source[/def check_display_paints\(.*?\n  end\n/m]
    refute_nil body, "expected to find check_display_paints in scripts/doctor.rb"

    assert_match(/agent_dir/, body,
      "check_display_paints must resolve the launcher from the injected agent_dir")
    refute_match(/["']message-display["']/, body,
      "check_display_paints must never hardcode the package's own hooks/message-display " \
      "launcher name; it must derive the installed launcher (plastic-message-display) via " \
      "display_hook_launcher_name, so it is the INSTALLED launcher that gets replayed, " \
      "never the package's own copy (R1)")
  end

  def test_paints_skips_on_hookless_harness # E5
    Dir.mktmpdir("plastic-display-e5") do |dir|
      claude_dir = File.join(dir, "claude")
      d = Doctor.new(plastic_home: File.join(dir, "home"), agents: agents_for(claude_dir))
      check = d.check_display_paints("codex", no_color: nil).first

      assert_equal "pass", check[:status]
      assert_includes check[:message], "plain by contract"
    end
  end

  def test_paints_fails_on_replay_timeout # E21
    Dir.mktmpdir("plastic-display-e21") do |dir|
      home = File.join(dir, "home")
      claude_dir = File.join(dir, "claude")
      FileUtils.mkdir_p(home)
      write_fixture(home)
      write_launcher(claude_dir, executable: true, content: "#!/bin/bash\nsleep 5\n")

      d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
      check = d.check_display_paints("claude", no_color: nil, timeout_seconds: 1).first

      assert_equal "fail", check[:status]
      assert_match(/time/i, check[:message])
    end
  end

  def test_paints_fails_when_fixture_missing # E22
    Dir.mktmpdir("plastic-display-e22-home") do |home|
      Dir.mktmpdir("plastic-display-e22-pkg") do |empty_pkg|
        claude_dir = File.join(home, "..", "claude-e22")
        FileUtils.mkdir_p(claude_dir)

        d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
        check = d.check_display_paints("claude", no_color: nil, package_root: empty_pkg).first

        assert_equal "fail", check[:status]
        assert_match(/fixture/i, check[:message])
      end
    end
  end

  # =========================================================================
  # HookReplay's env: extension (intent 331e, backwards-compatible with 331a)
  # =========================================================================

  def test_replay_env_keyword_merges_into_child_env_and_can_unset
    Dir.mktmpdir("hook-replay-env") do |tmp|
      launcher = File.join(tmp, "env-echo-hook")
      script = <<~RUBY
        #!/usr/bin/env ruby
        require "json"
        $stdin.read
        content = "NO_COLOR=\#{ENV["NO_COLOR"].inspect} PLASTIC_HOME=\#{ENV["PLASTIC_HOME"]}"
        puts JSON.generate("hookSpecificOutput" => { "hookEventName" => "MessageDisplay",
          "displayContent" => content })
      RUBY
      File.write(launcher, script)
      File.chmod(0o755, launcher)

      outs = HookReplay.replay(hook_path: launcher, tmp_root: tmp, text: "hi",
                                env: { "NO_COLOR" => nil, "PLASTIC_HOME" => "/injected/home" })
      content = HookReplay.final_display_content(outs)

      assert_includes content, "PLASTIC_HOME=/injected/home"
      assert_includes content, "NO_COLOR=nil"
    end
  end

  # =========================================================================
  # check_display_not_defeated (scripts/doctor.rb, full run only)
  # =========================================================================

  def test_warns_on_no_color # E6
    Dir.mktmpdir("plastic-display-e6") do |dir|
      home = File.join(dir, "home")
      claude_dir = File.join(dir, "claude")
      write_settings(claude_dir, hooks: {})

      d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
      check = d.check_display_not_defeated("claude", no_color: "1").first

      assert_equal "warn", check[:status]
      assert_includes check[:details].join(" | "), "NO_COLOR"
    end
  end

  def test_warns_on_config_ansi_screen_false # E7
    Dir.mktmpdir("plastic-display-e7") do |dir|
      home = File.join(dir, "home")
      claude_dir = File.join(dir, "claude")
      FileUtils.mkdir_p(home)
      write_settings(claude_dir, hooks: {})
      File.write(File.join(home, "config.yml"), "display:\n  ansi_screen: false\n")

      d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
      check = d.check_display_not_defeated("claude", no_color: nil).first

      assert_equal "warn", check[:status]
      assert_includes check[:details].join(" | "), "ansi_screen"
    end
  end

  def test_warns_on_verbose_setting # E8
    Dir.mktmpdir("plastic-display-e8") do |dir|
      home = File.join(dir, "home")
      claude_dir = File.join(dir, "claude")
      write_settings(claude_dir, hooks: {}, extra: { "verbose" => true })

      d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
      check = d.check_display_not_defeated("claude", no_color: nil).first

      assert_equal "warn", check[:status]
      assert_includes check[:details].join(" | "), "verbose"
    end
  end

  def test_not_defeated_details_name_the_transcript_view # E8
    Dir.mktmpdir("plastic-display-e8b") do |dir|
      home = File.join(dir, "home")
      claude_dir = File.join(dir, "claude")
      write_settings(claude_dir, hooks: {})

      d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
      check = d.check_display_not_defeated("claude", no_color: nil).first

      assert_equal "pass", check[:status], "a clean fixture carries no defeater"
      assert_includes check[:details].join(" | "), "Ctrl+O",
        "every result, pass or warn, must name the undetectable verbose transcript view"
    end
  end

  # =========================================================================
  # Wiring: --core scope, the full run, byte budget (E10, E11, E23)
  # =========================================================================

  def build_full_run_fixture
    dir = Dir.mktmpdir("plastic-display-full-run")
    home = File.join(dir, "home")
    claude_dir = File.join(dir, "claude")
    FileUtils.mkdir_p(home)
    write_fixture(home)
    launcher_path = write_working_launcher(claude_dir, color: true)
    write_settings(claude_dir, hooks: message_display_hooks(launcher_path))
    [dir, home, claude_dir]
  end

  def test_full_doctor_runs_display_category # E10
    dir, home, claude_dir = build_full_run_fixture
    d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
    names = d.run_checks("claude")[:checks].select { |c| c[:category] == "display" }.map { |c| c[:name] }

    assert_equal(
      %w[display_hook_registered display_hook_paints display_not_defeated display_surfaces_documented].sort,
      names.sort
    )
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  def test_core_doctor_runs_registration_check_only # E11
    dir, home, claude_dir = build_full_run_fixture
    d = Doctor.new(plastic_home: home, agents: agents_for(claude_dir))
    names = d.run_core_checks("claude")[:checks].select { |c| c[:category] == "display" }.map { |c| c[:name] }

    assert_equal ["display_hook_registered"], names
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  # E23: the existing test_core_require_loads_exactly_the_allowed_repo_files
  # (test/doctor_core_split_test.rb) must stay green UNCHANGED — proof that
  # display_hook_registered adds no new require to the boot path. This test
  # file does not duplicate that guard; it only asserts the two full-run
  # checks that DO need Open3/Timeout are absent from doctor_core.rb's own
  # source, so a future edit cannot quietly move them onto the boot path.
  def test_full_run_only_checks_are_defined_outside_doctor_core
    core_source = File.read(File.join(ROOT, "scripts", "lib", "doctor_core.rb"))
    refute_match(/def check_display_paints\b/, core_source)
    refute_match(/def check_display_not_defeated\b/, core_source)
    refute_match(/def check_display_surfaces_documented\b/, core_source)
  end

  # =========================================================================
  # Docs and CHANGELOG (E9, E24, E12)
  # =========================================================================

  def test_adapters_doc_surfaces_section_names_each_class # E9
    doc = File.read(File.join(ROOT, "docs", "reference", "harness-adapters.md"))
    section = doc[/^## Surfaces\n(.*?)(?=\n## |\z)/m, 1]

    refute_nil section, "expected a top-level ## Surfaces section in harness-adapters.md"
    ["Claude Code normal view", "agents view", "Codex", "claude -p", "verbose transcript view"].each do |literal|
      assert_includes section, literal, "## Surfaces section missing #{literal.inspect}"
    end
  end

  def test_internals_names_the_display_category # E24
    body = File.read(File.join(ROOT, "docs", "internals.md"))
    %w[display_hook_registered display_hook_paints display_not_defeated display_surfaces_documented].each do |name|
      assert_includes body, name
    end
    assert_includes body, "--core"
  end

  def test_changelog_names_display_checks # E12
    body = File.read(File.join(ROOT, "CHANGELOG.md"))
    %w[display_hook_registered display_hook_paints display_not_defeated display_surfaces_documented].each do |name|
      assert_includes body, name
    end
  end
end
