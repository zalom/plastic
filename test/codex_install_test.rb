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

  def test_install_codex_writes_agents_md_skills_and_generates_agent_tomls
    result = @core.install_for_agent("codex", false)

    assert result[:success]
    assert File.exist?(agents_md)
    assert_includes File.read(agents_md), InstallerCore::CODEX_SECTION_BEGIN_PREFIX

    skills = Dir.glob(File.join(@agent_dir, "skills", "plastic-*"))
    refute_empty skills, "skills must still be copied"

    agent_tomls = Dir.glob(File.join(@codex_home, "agents", "plastic-*.toml"))
    refute_empty agent_tomls, "codex agent role files must be generated as TOML under ~/.codex/agents"
    assert_empty Dir.glob(File.join(@agent_dir, "agents", "*.md")),
      "the codex leg must not write the dead ~/.agents/agents/*.md copy"

    manifest = JSON.parse(File.read(File.join(@agent_dir, "plastic-manifest.json")))
    manifest_keys = manifest["files"].keys
    refute manifest_keys.any? { |k| k.include?("AGENTS.md") },
      "AGENTS.md must never be manifest-tracked"
  end

  def test_install_codex_manifest_tracks_the_generated_tomls_one_per_source_agent
    @core.install_for_agent("codex", false)

    # Consultation agents (intent 185) pin `fable` in authored frontmatter, and
    # Codex has no fable alias, so generate_codex_agents skips them: one toml per
    # shipped agent EXCEPT those three.
    sources = Dir.glob(File.join(WORKTREE, "agents", "*.md"))
      .reject { |p| AgentModels::CONSULTATION_AGENTS.include?(File.basename(p, ".md")) }
    tomls = Dir.glob(File.join(@codex_home, "agents", "*.toml"))
    assert_equal sources.size, tomls.size, "one generated toml per shipped agent .md, excluding consultation agents"

    manifest = JSON.parse(File.read(File.join(@agent_dir, "plastic-manifest.json")))
    manifest_keys = manifest["files"].keys
    tomls.each do |t|
      assert_includes manifest_keys, t, "the manifest must track the generated toml #{t}"
    end
  end

  # --- Intent 102a: Codex agent TOML generation (escape helpers, field mapping, effort) ---

  def decode_toml_escapes(s)
    out = +""
    i = 0
    while i < s.length
      c = s[i]
      if c == "\\" && i + 1 < s.length
        nxt = s[i + 1]
        case nxt
        when "\\" then out << "\\"; i += 2
        when '"' then out << '"'; i += 2
        when "u"
          hex = s[i + 2, 4]
          out << [hex.to_i(16)].pack("U")
          i += 6
        else
          out << c
          i += 1
        end
      else
        out << c
        i += 1
      end
    end
    out
  end

  def test_toml_ml_escape_round_trips_quotes_backslash_triple_quote_newline_and_unicode
    input = "a\"b\\c\"\"\"d\neé"
    escaped = @core.toml_ml_escape(input)

    refute_includes escaped, '"""', "no bare triple-quote may survive escaping"
    assert_includes escaped, "\n", "the real newline must be preserved"
    assert_includes escaped, "é", "the unicode character must be preserved"
    assert_equal input, decode_toml_escapes(escaped), "the escape must round-trip losslessly"
  end

  def test_toml_ml_escape_normalizes_crlf_and_lone_cr_to_lf
    escaped = @core.toml_ml_escape("line1\r\nline2\rline3")
    assert_equal "line1\nline2\nline3", escaped
  end

  def test_toml_ml_escape_escapes_c0_controls_but_preserves_tab_and_newline
    escaped = @core.toml_ml_escape("a\x01b\tc\nd")
    expected_control_escape = "\\" + "u0001" # backslash + literal u0001, six characters
    assert_includes escaped, expected_control_escape
    assert_includes escaped, "\t", "tab must be preserved, not escaped"
    assert_includes escaped, "\n", "newline must be preserved, not escaped"
  end

  def test_toml_inline_escape_collapses_newlines_to_spaces
    escaped = @core.toml_inline_escape("line one\nline two\n  line three")
    refute_includes escaped, "\n"
    assert_equal "line one line two line three", escaped
  end

  def test_codex_model_fields_by_shape
    assert_equal 'model_reasoning_effort = "high"', @core.codex_model_fields("opus")
    assert_equal 'model_reasoning_effort = "medium"', @core.codex_model_fields("sonnet")
    assert_equal 'model_reasoning_effort = "low"', @core.codex_model_fields("haiku")
    assert_equal 'model = "gpt-5.4-codex"', @core.codex_model_fields("gpt-5.4-codex")
    assert_equal "", @core.codex_model_fields("")
    assert_equal "", @core.codex_model_fields(nil)
  end

  def test_render_codex_agent_toml_maps_frontmatter_and_carries_the_body_verbatim
    dir = Dir.mktmpdir("codex-agent-src")
    begin
      src = File.join(dir, "plastic-sample.md")
      File.write(src, <<~MD)
        ---
        name: plastic-sample
        description: A sample role for testing
        model: sonnet
        ---

        You are the sample role. This body has a "quote" in it.
      MD

      toml = @core.render_codex_agent_toml(src, nil)

      assert_match(/^name = "plastic-sample"$/, toml)
      assert_match(/^description = "A sample role for testing"$/, toml)
      assert_includes toml, 'model_reasoning_effort = "medium"'
      refute_match(/^model = /, toml)

      marker = 'developer_instructions = """'
      start = toml.index(marker)
      refute_nil start, "developer_instructions block must be present"
      finish = toml.index('"""', start + marker.length)
      refute_nil finish, "the developer_instructions triple-quote must be balanced"

      assert_includes toml, 'This body has a \\"quote\\" in it.',
        "the body must survive (escaped) inside developer_instructions"
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  def test_effort_per_tier_on_default_install_and_no_hardcoded_model
    @core.install_for_agent("codex", false)

    opus_toml = File.read(File.join(@codex_home, "agents", "plastic-enforcer.toml"))
    assert_includes opus_toml, 'model_reasoning_effort = "high"'
    refute_match(/^model = /, opus_toml)

    sonnet_toml = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))
    assert_includes sonnet_toml, 'model_reasoning_effort = "medium"'
    refute_match(/^model = /, sonnet_toml)

    Dir.glob(File.join(@codex_home, "agents", "plastic-*.toml")).each do |f|
      refute_includes File.read(f), 'model = "gpt',
        "no default-path toml may carry a hardcoded Codex model id"
    end
  end

  def test_haiku_alias_maps_to_low_effort_via_synthetic_render
    dir = Dir.mktmpdir("codex-agent-src")
    begin
      src = File.join(dir, "plastic-haiku-sample.md")
      File.write(src, <<~MD)
        ---
        name: plastic-haiku-sample
        description: haiku tier sample
        model: haiku
        ---

        body
      MD

      toml = @core.render_codex_agent_toml(src, nil)
      assert_includes toml, 'model_reasoning_effort = "low"'
      refute_match(/^model = /, toml)
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  def test_override_with_a_codex_model_id_wins_as_a_literal_model_and_drops_effort
    File.write(File.join(@home, "config.yml"),
               "agents:\n  models:\n    plastic-executor: gpt-5.4-codex\n")

    @core.install_for_agent("codex", false)

    toml = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))
    assert_includes toml, 'model = "gpt-5.4-codex"'
    refute_match(/^model_reasoning_effort = /, toml)
  end

  def test_override_with_a_tier_word_maps_to_effort_not_a_literal_model
    File.write(File.join(@home, "config.yml"),
               "agents:\n  models:\n    plastic-executor: haiku\n")

    @core.install_for_agent("codex", false)

    toml = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))
    assert_includes toml, 'model_reasoning_effort = "low"'
    refute_match(/^model = /, toml)
  end

  def test_regenerating_codex_agent_tomls_is_byte_identical
    @core.install_for_agent("codex", false)
    first = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))

    @core.install_for_agent("codex", false)
    second = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))

    assert_equal first, second, "regenerating via install_for_agent must be byte-identical"

    dir_a = Dir.mktmpdir("codex-toml-a")
    dir_b = Dir.mktmpdir("codex-toml-b")
    begin
      @core.generate_codex_agents(dir_a, models: {})
      @core.generate_codex_agents(dir_b, models: {})
      assert_equal File.read(File.join(dir_a, "plastic-executor.toml")),
                   File.read(File.join(dir_b, "plastic-executor.toml")),
                   "generate_codex_agents must produce byte-identical output across independent runs"
    ensure
      FileUtils.rm_rf(dir_a)
      FileUtils.rm_rf(dir_b)
    end
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
    FileUtils.mkdir_p(File.join(@codex_home, "agents"))
    File.write(File.join(@codex_home, "agents", "plastic-enforcer.toml"), codex_toml_fixture)
    FileUtils.mkdir_p(@codex_home)
    File.write(agents_md, @core.codex_section)

    checks = doctor_for(@codex_home).check_agent_registration("codex")

    assert checks.any? { |c| c[:name] == "skills_exist" }, "generic skills check must still run for codex"
    assert checks.any? { |c| c[:name] == "codex_agents_toml" }, "the codex TOML agents check must run"
    refute checks.any? { |c| c[:name] == "agents_exist" },
      "the flat .md agents check must no longer apply to codex"
  end

  # --- Intent 102a: doctor codex_agents_toml_check ---

  def codex_toml_fixture(name: "plastic-enforcer")
    <<~TOML
      name = "#{name}"
      description = "test agent"
      model_reasoning_effort = "high"
      developer_instructions = """
      body
      """
    TOML
  end

  def test_doctor_codex_agents_toml_passes_on_healthy_install
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    toml_check = checks.find { |c| c[:name] == "codex_agents_toml" }

    refute_nil toml_check
    assert_equal "pass", toml_check[:status]
  end

  def test_doctor_codex_agents_toml_fails_when_absent
    checks = doctor_for(@codex_home).check_agent_registration("codex")
    toml_check = checks.find { |c| c[:name] == "codex_agents_toml" }

    refute_nil toml_check
    assert_equal "fail", toml_check[:status]
  end

  def test_doctor_codex_agents_toml_fails_when_developer_instructions_missing
    FileUtils.mkdir_p(File.join(@codex_home, "agents"))
    malformed_path = File.join(@codex_home, "agents", "plastic-broken.toml")
    File.write(malformed_path, "name = \"plastic-broken\"\ndescription = \"broken\"\n")

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    toml_check = checks.find { |c| c[:name] == "codex_agents_toml" }

    refute_nil toml_check
    assert_equal "fail", toml_check[:status]
    assert(toml_check[:details].any? { |d| d.include?("plastic-broken.toml") })
  end

  def test_doctor_codex_checks_include_agents_md_and_hooks_alongside_toml_check
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_registration("codex")

    assert checks.any? { |c| c[:name] == "codex_agents_toml" }
    assert checks.any? { |c| c[:name] == "codex_agents_md" }
    assert checks.any? { |c| c[:name] == "codex_hooks_registered" }
  end

  # --- Intent 102a: uninstall prunes the generated agent tomls (manifest path, no new code) ---

  def test_uninstall_removes_generated_agent_tomls_via_the_manifest
    @core.install_for_agent("codex", false)
    tomls = Dir.glob(File.join(@codex_home, "agents", "plastic-*.toml"))
    refute_empty tomls, "the install must have generated at least one agent toml"

    @core.uninstall_agent("codex", @core.agent_config("codex"))

    assert_empty Dir.glob(File.join(@codex_home, "agents", "plastic-*.toml")),
      "uninstall must prune the generated agent tomls via the manifest"
  end

  # --- Intent 102, Step 5: install_codex hooks.json wiring ---

  def hooks_json_path
    File.join(@codex_home, "hooks.json")
  end

  def all_codex_hook_commands(data)
    (data["hooks"] || {}).flat_map do |_event, groups|
      Array(groups).flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
    end
  end

  def test_install_codex_fresh_create_writes_well_formed_hooks_json
    refute File.directory?(@codex_home), "home_dir must be absent before install (the owner's install-day path)"

    result = @core.install_for_agent("codex", false)

    assert result[:success]
    assert File.directory?(@codex_home)
    assert File.exist?(hooks_json_path)

    data = JSON.parse(File.read(hooks_json_path))
    commands = all_codex_hook_commands(data)
    assert commands.any? { |c| c.include?("codex-hook") && c.include?("code-gate") }
    assert commands.any? { |c| c.include?("codex-hook") && c.include?("gate-check") }

    pre_group = data["hooks"]["PreToolUse"].find { |g| g["matcher"] == "apply_patch" }
    refute_nil pre_group, "PreToolUse must register under the apply_patch matcher"
    post_group = data["hooks"]["PostToolUse"].find { |g| g["matcher"] == "apply_patch" }
    refute_nil post_group, "PostToolUse must register under the apply_patch matcher"
  end

  def test_install_codex_merges_into_existing_hooks_json_preserving_user_entry
    FileUtils.mkdir_p(@codex_home)
    user_hooks = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "SomeOtherTool", "hooks" => [{ "type" => "command", "command" => "/usr/local/bin/my-hook" }] },
        ],
      },
    }
    File.write(hooks_json_path, JSON.pretty_generate(user_hooks))

    @core.install_for_agent("codex", false)

    data = JSON.parse(File.read(hooks_json_path))
    user_group = data["hooks"]["PreToolUse"].find { |g| g["matcher"] == "SomeOtherTool" }
    refute_nil user_group, "the pre-existing user hook group must survive the merge"
    assert_equal "/usr/local/bin/my-hook", user_group["hooks"].first["command"]

    plastic_group = data["hooks"]["PreToolUse"].find { |g| g["matcher"] == "apply_patch" }
    refute_nil plastic_group, "Plastic's apply_patch group must be added alongside the user's"
  end

  def test_install_codex_is_idempotent_on_rerun
    @core.install_for_agent("codex", false)
    first = JSON.parse(File.read(hooks_json_path))

    @core.install_for_agent("codex", false)
    second = JSON.parse(File.read(hooks_json_path))

    assert_equal first, second, "re-running install must not duplicate hook groups"
    pre_groups = second["hooks"]["PreToolUse"].select { |g| g["matcher"] == "apply_patch" }
    assert_equal 1, pre_groups.size, "exactly one apply_patch PreToolUse group after re-run"
  end

  def test_install_codex_does_not_manifest_track_hooks_json
    @core.install_for_agent("codex", false)

    manifest = JSON.parse(File.read(File.join(@agent_dir, "plastic-manifest.json")))
    manifest_keys = manifest["files"].keys
    refute manifest_keys.any? { |k| k.include?("hooks.json") },
      "hooks.json must never be manifest-tracked (partial-ownership file)"
  end

  # --- Intent 102, Step 6: uninstall hooks.json wiring ---

  def test_uninstall_strips_exactly_plastic_hooks_json_groups
    FileUtils.mkdir_p(@codex_home)
    user_hooks = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "SomeOtherTool", "hooks" => [{ "type" => "command", "command" => "/usr/local/bin/my-hook" }] },
        ],
      },
    }
    File.write(hooks_json_path, JSON.pretty_generate(user_hooks))

    @core.install_for_agent("codex", false)
    @core.uninstall_agent("codex", @core.agent_config("codex"))

    data = JSON.parse(File.read(hooks_json_path))
    refute all_codex_hook_commands(data).any? { |c| c.include?("codex-hook") },
      "no codex-hook command may survive uninstall"
  end

  def test_uninstall_preserves_pre_existing_user_hook_entry
    FileUtils.mkdir_p(@codex_home)
    user_hooks = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "SomeOtherTool", "hooks" => [{ "type" => "command", "command" => "/usr/local/bin/my-hook" }] },
        ],
      },
    }
    File.write(hooks_json_path, JSON.pretty_generate(user_hooks))

    @core.install_for_agent("codex", false)
    @core.uninstall_agent("codex", @core.agent_config("codex"))

    data = JSON.parse(File.read(hooks_json_path))
    user_group = data["hooks"]["PreToolUse"].find { |g| g["matcher"] == "SomeOtherTool" }
    refute_nil user_group, "the user's own hook entry must survive uninstall byte-preserved"
    assert_equal "/usr/local/bin/my-hook", user_group["hooks"].first["command"]
  end

  def test_uninstall_removes_plastic_created_hooks_json_with_nothing_else
    @core.install_for_agent("codex", false)
    assert File.exist?(hooks_json_path)

    @core.uninstall_agent("codex", @core.agent_config("codex"))

    refute File.exist?(hooks_json_path), "a Plastic-created hooks.json with nothing else left must be removed"
  end

  def test_uninstall_with_no_plastic_groups_is_a_noop
    FileUtils.mkdir_p(@codex_home)
    user_hooks = {
      "hooks" => {
        "PreToolUse" => [
          { "matcher" => "SomeOtherTool", "hooks" => [{ "type" => "command", "command" => "/usr/local/bin/my-hook" }] },
        ],
      },
    }
    seed = JSON.pretty_generate(user_hooks)
    File.write(hooks_json_path, seed)

    result = @core.uninstall_agent("codex", @core.agent_config("codex"))

    assert result[:success]
    assert_equal JSON.parse(seed), JSON.parse(File.read(hooks_json_path)),
      "a hooks.json with no Plastic groups must be untouched"
  end

  # --- Intent 102, Step 7: doctor codex_hooks_registered + config.toml advisory ---

  def config_toml_path
    File.join(@codex_home, "config.toml")
  end

  def test_doctor_codex_hooks_registered_passes_on_healthy_install
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    hooks_check = checks.find { |c| c[:name] == "codex_hooks_registered" }

    refute_nil hooks_check
    assert_equal "pass", hooks_check[:status]
  end

  def test_doctor_codex_hooks_registered_fails_when_missing
    checks = doctor_for(@codex_home).check_agent_registration("codex")
    hooks_check = checks.find { |c| c[:name] == "codex_hooks_registered" }

    refute_nil hooks_check
    assert_equal "fail", hooks_check[:status]
  end

  def test_doctor_codex_hooks_registered_fails_when_drifted
    @core.install_for_agent("codex", false)
    data = JSON.parse(File.read(hooks_json_path))
    # Simulate drift: drop the create-gate command from the live file.
    data["hooks"]["PreToolUse"].each do |g|
      next unless g["matcher"] == "apply_patch"
      g["hooks"].reject! { |h| h["command"].include?("create-gate") }
    end
    File.write(hooks_json_path, JSON.pretty_generate(data))

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    hooks_check = checks.find { |c| c[:name] == "codex_hooks_registered" }

    refute_nil hooks_check
    assert_equal "fail", hooks_check[:status]
    assert(hooks_check[:details].any? { |d| d.include?("create-gate") })
  end

  def test_doctor_config_toml_advisory_warns_on_hooks_disabled
    FileUtils.mkdir_p(@codex_home)
    File.write(config_toml_path, "[features]\nhooks = false\n")

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    advisory = checks.find { |c| c[:name] == "codex_config_advisory" }

    refute_nil advisory
    assert_equal "warn", advisory[:status]
    assert_includes advisory[:message], "hooks are disabled"
  end

  def test_doctor_config_toml_advisory_warns_on_deprecated_alias
    FileUtils.mkdir_p(@codex_home)
    File.write(config_toml_path, "codex_hooks = false\n")

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    advisory = checks.find { |c| c[:name] == "codex_config_advisory" }

    refute_nil advisory
    assert_equal "warn", advisory[:status]
  end

  def test_doctor_config_toml_advisory_warns_on_read_only_sandbox
    FileUtils.mkdir_p(@codex_home)
    File.write(config_toml_path, "sandbox_mode = \"read-only\"\n")

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    advisory = checks.find { |c| c[:name] == "codex_config_advisory" }

    refute_nil advisory
    assert_equal "warn", advisory[:status]
    assert_includes advisory[:message], "sandbox_mode"
  end

  def test_doctor_config_toml_advisory_silent_when_clean
    FileUtils.mkdir_p(@codex_home)
    File.write(config_toml_path, "model = \"gpt-test\"\n")

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    advisory = checks.find { |c| c[:name] == "codex_config_advisory" }

    assert_nil advisory, "a clean config.toml must produce no advisory check"
  end

  def test_doctor_config_toml_advisory_silent_when_absent
    checks = doctor_for(@codex_home).check_agent_registration("codex")
    advisory = checks.find { |c| c[:name] == "codex_config_advisory" }

    assert_nil advisory, "an absent config.toml must produce no advisory check"
  end

  def test_doctor_agents_md_check_still_runs_alongside_hooks_check
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_registration("codex")

    assert checks.any? { |c| c[:name] == "codex_agents_md" }
    assert checks.any? { |c| c[:name] == "codex_hooks_registered" }
  end

  def test_doctor_never_writes_config_toml
    FileUtils.mkdir_p(@codex_home)
    File.write(config_toml_path, "sandbox_mode = \"read-only\"\n")
    before = File.read(config_toml_path)
    before_mtime = File.mtime(config_toml_path)

    doctor_for(@codex_home).check_agent_registration("codex")

    assert_equal before, File.read(config_toml_path), "doctor must never modify config.toml content"
    assert_equal before_mtime, File.mtime(config_toml_path), "doctor must never touch config.toml"
  end
end
