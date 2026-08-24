require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

require_relative "../scripts/doctor"

# Doctor's stray-skill backstop (intent 158a, AC15): an installed plastic-* skill
# directory with no corresponding entry in the current install manifest is a leftover
# (e.g. an old-name copy a rename's prune should have removed, or one predating the
# manifest). Complements flat_skills_check, which only confirms at least one skill is
# present and says nothing about drift between what's installed and what's tracked.
#
# Hermetic: self-contained throwaway plastic_home + agent dir under Dir.mktmpdir, a
# Doctor instance with agents: injected so it never touches ~/.claude. No eval, no
# ENV/global seam.
class DoctorStraySkillsTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("doctor-stray-home")
    @agent_dir = Dir.mktmpdir("doctor-stray-agent")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@agent_dir)
  end

  def doctor
    Doctor.new(plastic_home: @home, agents: { "claude" => { name: "Claude Code", dir: @agent_dir } })
  end

  def manifest_path
    File.join(@agent_dir, "plastic", "manifest.json")
  end

  def install_skill(name)
    dir = File.join(@agent_dir, "skills", name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), "# #{name}")
  end

  def write_manifest(tracked_skill_names)
    FileUtils.mkdir_p(File.dirname(manifest_path))
    files = tracked_skill_names.each_with_object({}) do |name, h|
      path = File.join(@agent_dir, "skills", name, "SKILL.md")
      h[path] = Digest::SHA256.file(path).hexdigest
    end
    File.write(manifest_path, JSON.pretty_generate({ "files" => files }))
  end

  def test_clean_install_reports_no_stray
    install_skill("plastic-doctor")
    write_manifest(["plastic-doctor"])

    check = doctor.stray_skills_check(@agent_dir, "--claude", manifest_path)

    refute_nil check, "manifest is present, the check must run"
    assert_equal "pass", check[:status]
    assert_empty check[:details] || []
  end

  def test_planted_stray_is_flagged_with_a_fix
    install_skill("plastic-doctor")
    write_manifest(["plastic-doctor"]) # manifest written BEFORE the stray is planted

    # Plant a stray: an installed skill dir with no manifest entry (e.g. a leftover
    # old-name copy after a rename).
    install_skill("plastic-creating-intent")

    check = doctor.stray_skills_check(@agent_dir, "--claude", manifest_path)

    refute_nil check
    assert_equal "warn", check[:status]
    assert check[:fixable], "a stray must be reported as fixable"
    assert check[:fix_hint], "a stray must carry a fix hint"
    assert_match(/plastic@latest/, check[:fix_hint])
    assert_includes check[:details], "plastic-creating-intent"
    refute_includes check[:details], "plastic-doctor", "the tracked skill must not be named as a stray"
  end

  # Intent 276: a missing or unreadable manifest used to make this check
  # return nil and vanish from the report entirely, exactly the state where
  # stray-skill detection is needed most. It now warns loudly instead,
  # naming the installed dirs it cannot verify ownership for.
  def test_missing_manifest_warns_loudly_when_skills_are_installed
    install_skill("plastic-doctor")
    # No manifest.json written at all.

    check = doctor.stray_skills_check(@agent_dir, "--claude", manifest_path)

    refute_nil check, "stray_skills_check must never return nil"
    assert_equal "warn", check[:status]
    assert_includes check[:details], "plastic-doctor"
  end

  # The other half of the same fix: no skills installed AND no manifest is a
  # genuinely healthy "nothing to verify" state, not a second red alongside
  # skills_exist's own fail for that state.
  def test_missing_manifest_passes_when_nothing_is_installed
    # No skills installed, no manifest.json.
    check = doctor.stray_skills_check(@agent_dir, "--claude", manifest_path)

    refute_nil check, "stray_skills_check must never return nil"
    assert_equal "pass", check[:status]
    assert_match(/nothing to verify/, check[:message])
  end

  # AC10: the stray message/fix_hint must name the reserved-prefix rule and
  # the rename remedy, not just "stale, re-install". Asserted on a stable
  # substring, not the whole sentence.
  def test_stray_message_states_the_reserved_prefix_rule
    install_skill("plastic-doctor")
    write_manifest(["plastic-doctor"])
    install_skill("plastic-creating-intent")

    check = doctor.stray_skills_check(@agent_dir, "--claude", manifest_path)
    text = "#{check[:message]} #{check[:fix_hint]}"

    assert_includes text, "reserved"
    assert_includes text, "rename"
  end

  # AC11: the missing-manifest fix reaches a non-Claude agent directory
  # (Codex ~/.agents shape) through the same shared check_flat_skills_and_stray
  # call path codex/hermes actually use, with no second implementation.
  def test_missing_manifest_warns_through_a_non_claude_agent_dir
    install_skill("plastic-doctor")
    # No manifest.json written at all.

    codex_doctor = Doctor.new(plastic_home: @home, agents: { "codex" => { name: "Codex CLI", dir: @agent_dir } })
    checks = codex_doctor.check_flat_skills_and_stray("codex", @agent_dir)
    stray_check = checks.find { |c| c[:name] == "stray_skills" }

    refute_nil stray_check, "check_flat_skills_and_stray must include stray_skills"
    assert_equal "warn", stray_check[:status]
    assert_includes stray_check[:details], "plastic-doctor"
  end

  def test_wired_into_claude_registration_when_a_manifest_exists
    install_skill("plastic-doctor")
    write_manifest(["plastic-doctor"])
    install_skill("plastic-creating-intent")

    checks = doctor.check_claude_registration(@agent_dir)
    stray_check = checks.find { |c| c[:name] == "stray_skills" }

    refute_nil stray_check, "check_claude_registration must include the stray_skills check"
    assert_equal "warn", stray_check[:status]
  end

  def test_wired_into_generic_agent_registration_when_a_manifest_exists
    generic_manifest_path = File.join(@agent_dir, "plastic", "manifest.json")
    FileUtils.mkdir_p(File.join(@agent_dir, "plastic"))
    install_skill("plastic-doctor")
    files = { File.join(@agent_dir, "skills", "plastic-doctor", "SKILL.md") =>
                Digest::SHA256.file(File.join(@agent_dir, "skills", "plastic-doctor", "SKILL.md")).hexdigest }
    File.write(generic_manifest_path, JSON.pretty_generate({ "files" => files }))
    install_skill("plastic-creating-intent")

    codex_doctor = Doctor.new(plastic_home: @home, agents: { "codex" => { name: "Codex CLI", dir: @agent_dir } })
    checks = codex_doctor.check_generic_agent_registration("codex", @agent_dir)
    stray_check = checks.find { |c| c[:name] == "stray_skills" }

    refute_nil stray_check, "check_generic_agent_registration must include the stray_skills check"
    assert_equal "warn", stray_check[:status]
  end
end
