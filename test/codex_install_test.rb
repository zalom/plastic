require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

require_relative "../scripts/lib/installer_core"
require_relative "../scripts/doctor"

# Codex adapter core (intent 33a): the two-root schema (`home_dir`), the AGENTS.md
# marked-section injector (create/append/replace/refuse), install_codex wiring, the
# surgical uninstall strip, and the doctor codex_agents_md check. Hermetic: throwaway
# tmpdirs, injected package_root/plastic_home/agents, no live API calls, no ambient
# session id.
class CodexInstallTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)

  def setup
    @home = Dir.mktmpdir("codex-test")            # plastic_home
    @agent_dir = Dir.mktmpdir("codex-agents")      # ~/.agents equivalent (skills+agents)
    @codex_home = File.join(@home, "codex-home")   # ~/.codex equivalent (AGENTS.md)
    @agents = [{ key: "codex", name: "Codex CLI", dir: @agent_dir,
                 home_dir: @codex_home, flag: "--codex" }]
    @core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home,
                               agents: @agents, version: "1.0.0-test")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@agent_dir)
  end

  def agents_md
    File.join(@codex_home, "AGENTS.md")
  end

  def doctor_for(home_dir)
    Doctor.new(plastic_home: @home,
               agents: { "codex" => { name: "Codex CLI", dir: @agent_dir, home_dir: home_dir } })
  end

  # --- Step 1: two-root schema ---

  def test_default_agents_codex_entry_has_home_dir
    codex = InstallerCore::DEFAULT_AGENTS.find { |a| a[:key] == "codex" }
    claude = InstallerCore::DEFAULT_AGENTS.find { |a| a[:key] == "claude" }
    hermes = InstallerCore::DEFAULT_AGENTS.find { |a| a[:key] == "hermes" }

    assert codex[:home_dir].end_with?(".codex")
    refute claude.key?(:home_dir), "claude must not gain a home_dir key"
    refute hermes.key?(:home_dir), "hermes must not gain a home_dir key"
  end

  def test_doctor_default_agents_codex_entry_has_home_dir
    codex = Doctor::DEFAULT_AGENTS["codex"]
    assert codex[:home_dir].end_with?(".codex")
    refute Doctor::DEFAULT_AGENTS["claude"].key?(:home_dir)
    refute Doctor::DEFAULT_AGENTS["hermes"].key?(:home_dir)
  end

  def test_agent_config_resolves_home_dir
    config = @core.agent_config("codex")
    assert_equal @codex_home, config[:home_dir]
  end

  # --- Step 2: AGENTS.md marked-section injector ---

  def test_injector_create_state_writes_exactly_the_section
    result = @core.inject_codex_agents_md(agents_md)

    assert_equal :created, result
    assert_equal @core.codex_section, File.read(agents_md)
  end

  def test_injector_append_state_preserves_pre_existing_content
    FileUtils.mkdir_p(@codex_home)
    seed = "# My rules\n\nkeep this\n"
    File.write(agents_md, seed)

    result = @core.inject_codex_agents_md(agents_md)
    content = File.read(agents_md)

    assert_equal :appended, result
    assert content.start_with?(seed), "pre-existing content must be preserved"
    assert_includes content, InstallerCore::CODEX_SECTION_BEGIN_PREFIX
    assert_includes content, InstallerCore::CODEX_SECTION_END
  end

  def test_injector_replace_state_is_idempotent
    @core.inject_codex_agents_md(agents_md)
    first = File.read(agents_md)

    result = @core.inject_codex_agents_md(agents_md)
    second = File.read(agents_md)

    assert_equal :replaced, result
    assert_equal first, second, "re-injecting the same body must be byte-identical"
    assert_equal 1, second.scan(InstallerCore::CODEX_SECTION_BEGIN_PREFIX).size
    assert_equal 1, second.scan(InstallerCore::CODEX_SECTION_END).size
  end

  def test_injector_replace_with_change_keeps_only_the_new_section
    @core.inject_codex_agents_md(agents_md, body: "Body A\n")
    first_hash = File.read(agents_md)[/hash:(\w+)/, 1]

    result = @core.inject_codex_agents_md(agents_md, body: "Body B\n")
    content = File.read(agents_md)
    second_hash = content[/hash:(\w+)/, 1]

    assert_equal :replaced, result
    refute_equal first_hash, second_hash, "the hash must change when the body changes"
    assert_equal 1, content.scan(InstallerCore::CODEX_SECTION_BEGIN_PREFIX).size
    assert_includes content, "Body B"
    refute_includes content, "Body A"
  end

  def test_injector_refuses_on_corrupt_section
    FileUtils.mkdir_p(@codex_home)
    corrupt = "#{InstallerCore::CODEX_SECTION_BEGIN_PREFIX} hash:deadbeef1234 -->\nno end marker here\n"
    File.write(agents_md, corrupt)

    result = @core.inject_codex_agents_md(agents_md)

    assert_equal :refused, result
    assert_equal corrupt, File.read(agents_md), "a corrupt section must leave the file untouched"
  end

  def test_body_is_under_1kib_and_has_no_em_dash
    assert InstallerCore::CODEX_AGENTS_MD_BODY.bytesize < 1024
    refute_includes InstallerCore::CODEX_AGENTS_MD_BODY, "—"
  end

  # --- Step 3: install_codex wiring ---

  def test_install_codex_writes_agents_md_and_copies_skills_and_agents
    result = @core.install_for_agent("codex", false)

    assert result[:success]
    assert File.exist?(agents_md)
    assert_includes File.read(agents_md), InstallerCore::CODEX_SECTION_BEGIN_PREFIX

    skills = Dir.glob(File.join(@agent_dir, "skills", "plastic-*"))
    refute_empty skills, "skills must still be copied"

    agent_roles = Dir.glob(File.join(@agent_dir, "agents", "*.md"))
    refute_empty agent_roles, "agent role files must still be copied"

    manifest = JSON.parse(File.read(File.join(@agent_dir, "plastic-manifest.json")))
    manifest_keys = manifest["files"].keys
    refute manifest_keys.any? { |k| k.include?("AGENTS.md") },
      "AGENTS.md must never be manifest-tracked"
  end

  # --- Step 4: surgical uninstall strip ---

  def test_uninstall_round_trip_preserves_pre_existing_content
    FileUtils.mkdir_p(@codex_home)
    seed = "# My rules\n\nkeep this\n"
    File.write(agents_md, seed)

    @core.install_for_agent("codex", false)
    @core.uninstall_agent("codex", @core.agent_config("codex"))

    assert_equal seed, File.read(agents_md), "pre-existing user content must round-trip byte-identical"
  end

  def test_uninstall_removes_plastic_created_agents_md
    @core.install_for_agent("codex", false)
    assert File.exist?(agents_md)

    @core.uninstall_agent("codex", @core.agent_config("codex"))

    refute File.exist?(agents_md), "a Plastic-created AGENTS.md must be removed entirely"
  end

  def test_uninstall_with_no_plastic_section_is_a_noop
    FileUtils.mkdir_p(@codex_home)
    seed = "# unrelated file\n"
    File.write(agents_md, seed)

    result = @core.uninstall_agent("codex", @core.agent_config("codex"))

    assert result[:success]
    assert_equal seed, File.read(agents_md), "a file with no Plastic section must be untouched"
  end

  # --- Step 5: doctor codex check ---

  def test_doctor_passes_when_section_is_healthy
    FileUtils.mkdir_p(File.join(@agent_dir, "skills", "plastic-doctor"))
    File.write(File.join(@agent_dir, "skills", "plastic-doctor", "SKILL.md"), "# doctor")
    FileUtils.mkdir_p(File.join(@agent_dir, "agents"))
    File.write(File.join(@agent_dir, "agents", "plastic-enforcer.md"), "# enforcer")
    FileUtils.mkdir_p(@codex_home)
    File.write(agents_md, @core.codex_section)

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    codex_check = checks.find { |c| c[:name] == "codex_agents_md" }

    refute_nil codex_check
    assert_equal "pass", codex_check[:status]
  end

  def test_doctor_fails_when_section_missing
    checks = doctor_for(@codex_home).check_agent_registration("codex")
    codex_check = checks.find { |c| c[:name] == "codex_agents_md" }

    refute_nil codex_check
    assert_equal "fail", codex_check[:status]
  end

  def test_doctor_fails_when_section_corrupt
    FileUtils.mkdir_p(@codex_home)
    File.write(agents_md, "#{InstallerCore::CODEX_SECTION_BEGIN_PREFIX} hash:abc -->\nno end\n")

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    codex_check = checks.find { |c| c[:name] == "codex_agents_md" }

    refute_nil codex_check
    assert_equal "fail", codex_check[:status]
  end

  def test_doctor_generic_checks_still_run_for_codex
    FileUtils.mkdir_p(File.join(@agent_dir, "skills", "plastic-doctor"))
    File.write(File.join(@agent_dir, "skills", "plastic-doctor", "SKILL.md"), "# doctor")
    FileUtils.mkdir_p(File.join(@agent_dir, "agents"))
    File.write(File.join(@agent_dir, "agents", "plastic-enforcer.md"), "# enforcer")
    FileUtils.mkdir_p(@codex_home)
    File.write(agents_md, @core.codex_section)

    checks = doctor_for(@codex_home).check_agent_registration("codex")

    assert checks.any? { |c| c[:name] == "skills_exist" }, "generic skills check must still run for codex"
    assert checks.any? { |c| c[:name] == "agents_exist" }, "generic agents check must still run for codex"
  end
end
