require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "digest"
require "stringio"
require "open3"
require "rbconfig"

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
    # Pre-created, mirroring @agent_dir: since intent 198 (Decision D1), Codex's
    # OWN home is the presence signal install_for_agent probes, so a fixture
    # exercising install_codex must already have it (a real machine only gets
    # this far because Codex itself created ~/.codex on its own install).
    FileUtils.mkdir_p(@codex_home)
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

  def doctor_for(home_dir, runner: nil)
    Doctor.new(plastic_home: @home,
               agents: { "codex" => { name: "Codex CLI", dir: @agent_dir, home_dir: home_dir } },
               **(runner ? { runner: runner } : {}))
  end

  def version_floor_check(home_dir, runner)
    doctor_for(home_dir, runner: runner)
      .check_codex_registration("codex", @agent_dir)
      .find { |c| c[:name] == "codex_version_floor" }
  end

  # 1. Falsifiable: below floor -> warn naming the 0.123.0 floor
  def test_codex_version_floor_below_floor_warns
    runner = ->(_args) { ["codex-cli 0.100.0\n", true] }
    c = version_floor_check(@codex_home, runner)
    assert_equal "warn", c[:status]
    assert_includes c[:message], "0.123.0"
  end

  # 2. Falsifiable: empty output on a PRESENT home is undetectable warn, not pass, not silence
  def test_codex_version_floor_undetectable_warns_distinctly
    runner = ->(_args) { ["", false] }
    c = version_floor_check(@codex_home, runner)
    assert_equal "warn", c[:status]
    assert_match(/could not determine/i, c[:message])
  end

  # 3. Unparseable output also -> undetectable warn
  def test_codex_version_floor_unparseable_warns
    runner = ->(_args) { ["garble\n", true] }
    c = version_floor_check(@codex_home, runner)
    assert_equal "warn", c[:status]
    assert_match(/could not determine/i, c[:message])
  end

  # 4. At/above floor -> explicit pass
  def test_codex_version_floor_at_or_above_floor_passes
    ["codex-cli 0.123.0\n", "codex-cli 0.144.4\n"].each do |out|
      c = version_floor_check(@codex_home, ->(_args) { [out, true] })
      assert_equal "pass", c[:status], "expected pass for #{out.strip}"
    end
  end

  # 5. Absent ~/.codex home -> no check emitted (nil)
  def test_codex_version_floor_absent_home_emits_nothing
    absent = File.join(@home, "no-such-codex")
    c = version_floor_check(absent, ->(_args) { ["codex-cli 0.100.0\n", true] })
    assert_nil c
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

  def test_default_agents_entries_carry_a_skill_prefix
    codex = InstallerCore::DEFAULT_AGENTS.find { |a| a[:key] == "codex" }
    claude = InstallerCore::DEFAULT_AGENTS.find { |a| a[:key] == "claude" }
    hermes = InstallerCore::DEFAULT_AGENTS.find { |a| a[:key] == "hermes" }

    assert_equal "/", claude[:skill_prefix]
    assert_equal "$", codex[:skill_prefix]
    refute hermes.key?(:skill_prefix), "hermes is a future adapter, same as home_dir"
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

  def test_body_teaches_dollar_prefix_invocation
    body = InstallerCore::CODEX_AGENTS_MD_BODY
    assert_includes body, "$plastic-<name>"
    assert_includes body, "$plastic-doctor"
    assert_match(/implicitly.*description/, body)
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

    manifest = JSON.parse(File.read(File.join(@agent_dir, "plastic", "manifest.json")))
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

    manifest = JSON.parse(File.read(File.join(@agent_dir, "plastic", "manifest.json")))
    manifest_keys = manifest["files"].keys
    tomls.each do |t|
      assert_includes manifest_keys, t, "the manifest must track the generated toml #{t}"
    end
  end

  # --- Intent 210, D2: uniform per-agent record dir + legacy manifest migration ---

  def test_install_codex_writes_the_uniform_record_dir_and_no_legacy_manifest
    result = @core.install_for_agent("codex", false)

    assert result[:success]
    assert File.exist?(File.join(@agent_dir, "plastic", "VERSION")),
      "codex must write its VERSION into the uniform record dir"
    assert_equal "1.0.0-test\n", File.read(File.join(@agent_dir, "plastic", "VERSION"))
    assert File.exist?(File.join(@agent_dir, "plastic", "manifest.json")),
      "codex must write its manifest into the uniform record dir"
    refute File.exist?(File.join(@agent_dir, "plastic-manifest.json")),
      "the legacy flat manifest must never be (re)written"
  end

  def test_manifest_path_for_resolves_to_the_uniform_path_for_every_agent
    config = { dir: @agent_dir }
    assert_equal File.join(@agent_dir, "plastic", "manifest.json"), @core.manifest_path_for("codex", config)
    assert_equal File.join(@agent_dir, "plastic", "manifest.json"), @core.manifest_path_for("hermes", config)
    assert_equal File.join(@agent_dir, "plastic", "manifest.json"), @core.manifest_path_for("claude", config)
  end

  # Falsifiable migration check (intent 210, B5): a pre-migration install left files
  # tracked only in the legacy flat manifest. A fresh install that no longer ships one
  # of those files must still prune it, proving the legacy list was unioned into
  # old_files rather than silently dropped.
  def test_legacy_manifest_files_no_longer_shipped_are_pruned_on_migration
    stale = File.join(@agent_dir, "skills", "plastic-long-gone", "SKILL.md")
    FileUtils.mkdir_p(File.dirname(stale))
    File.write(stale, "# stale\n")
    legacy_manifest = File.join(@agent_dir, "plastic-manifest.json")
    File.write(legacy_manifest, JSON.generate(
      "version" => "1", "files" => { stale => Digest::SHA256.file(stale).hexdigest }
    ))

    result = @core.install_for_agent("codex", false)

    refute File.exist?(stale), "a file tracked only by the legacy manifest must be pruned on migration"
    refute File.exist?(legacy_manifest), "the legacy manifest must be deleted once migrated"
    assert result[:pruned].to_i.positive?, "the migration prune must be reflected in the result"
  end

  def test_doctor_check_manifest_sync_agrees_with_a_freshly_installed_codex_fixture
    @core.distribute(:install) # writes the GLOBAL manifest check_manifest_sync also verifies
    @core.install_for_agent("codex", false)

    doctor = Doctor.new(plastic_home: @home,
                         agents: { "codex" => { name: "Codex CLI", dir: @agent_dir, home_dir: @codex_home } })
    checks = doctor.check_manifest_sync("codex")
    assert checks.all? { |c| c[:status] == "pass" },
      "installer and doctor must agree on the record path: #{checks.map { |c| [c[:name], c[:status]] }}"
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
    assert_equal %(model = "gpt-5.6-sol"\nmodel_reasoning_effort = "high"), @core.codex_model_fields("opus")
    assert_equal %(model = "gpt-5.6-terra"\nmodel_reasoning_effort = "medium"), @core.codex_model_fields("sonnet")
    assert_equal %(model = "gpt-5.6-luna"\nmodel_reasoning_effort = "low"), @core.codex_model_fields("haiku")
    assert_equal 'model = "gpt-5.4-codex"', @core.codex_model_fields("gpt-5.4-codex")
    assert_equal "", @core.codex_model_fields("")
    assert_equal "", @core.codex_model_fields(nil)
  end

  def test_codex_model_by_alias_resolves_ids
    assert_equal "gpt-5.6-sol", AgentModels.codex_model_for("opus")
    assert_equal "gpt-5.6-terra", AgentModels.codex_model_for("sonnet")
    assert_equal "gpt-5.6-luna", AgentModels.codex_model_for("haiku")
    assert_nil AgentModels.codex_model_for("gpt-5.4-mini")
    assert_nil AgentModels.codex_model_for(nil)
  end

  def test_codex_tier_alias_emits_model_then_effort
    %w[opus sonnet haiku].each do |a|
      out = @core.codex_model_fields(a)
      assert_match(/\Amodel = "gpt-5\.6-[a-z]+"\nmodel_reasoning_effort = "(high|medium|low)"\z/, out)
    end
  end

  def test_reasoning_roles_get_stronger_model_and_higher_effort_than_executors
    reasoning = @core.codex_model_fields(AgentModels::TIER_DEFAULTS["plastic-enforcer"])  # opus
    executor  = @core.codex_model_fields(AgentModels::TIER_DEFAULTS["plastic-executor"]) # sonnet
    assert_includes reasoning, 'model = "gpt-5.6-sol"'
    assert_includes reasoning, 'model_reasoning_effort = "high"'
    assert_includes executor, 'model = "gpt-5.6-terra"'
    assert_includes executor, 'model_reasoning_effort = "medium"'
    refute_equal reasoning, executor
  end

  def test_agents_models_codex_tier_override_selects_model_and_effort
    # override plastic-executor to the opus tier via agents.models.codex.*; expect sol/high to win.
    File.write(File.join(@home, "config.yml"),
               "agents:\n  models:\n    codex:\n      plastic-executor: opus\n")
    @core.install_for_agent("codex", false)
    toml = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))
    assert_includes toml, 'model = "gpt-5.6-sol"'
    assert_includes toml, 'model_reasoning_effort = "high"'
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
      assert_includes toml, 'model = "gpt-5.6-terra"'

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

  def test_model_and_effort_per_tier_on_default_install
    @core.install_for_agent("codex", false)

    opus_toml = File.read(File.join(@codex_home, "agents", "plastic-enforcer.toml"))
    assert_includes opus_toml, 'model = "gpt-5.6-sol"'
    assert_includes opus_toml, 'model_reasoning_effort = "high"'

    sonnet_toml = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))
    assert_includes sonnet_toml, 'model = "gpt-5.6-terra"'
    assert_includes sonnet_toml, 'model_reasoning_effort = "medium"'
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
      assert_includes toml, 'model = "gpt-5.6-luna"'
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  # Codex-scoped config (intent 185 final design): agents.models is
  # harness-scoped, so a Codex override must be written under
  # agents.models.codex.* to reach the Codex TOML render.
  def test_override_with_a_codex_model_id_wins_as_a_literal_model_and_drops_effort
    File.write(File.join(@home, "config.yml"),
               "agents:\n  models:\n    codex:\n      plastic-executor: gpt-5.4-codex\n")

    @core.install_for_agent("codex", false)

    toml = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))
    assert_includes toml, 'model = "gpt-5.4-codex"'
    refute_match(/^model_reasoning_effort = /, toml)
  end

  def test_override_with_a_tier_word_maps_to_model_and_effort
    File.write(File.join(@home, "config.yml"),
               "agents:\n  models:\n    codex:\n      plastic-executor: haiku\n")

    @core.install_for_agent("codex", false)

    toml = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))
    assert_includes toml, 'model_reasoning_effort = "low"'
    assert_includes toml, 'model = "gpt-5.6-luna"'
  end

  # The literal-model-id-leak regression proof (intent 185 final design): a
  # Claude-scoped or legacy flat override must NEVER surface in a generated
  # Codex TOML. Writing the SAME override under agents.models.plastic-executor
  # (flat, read as claude) must leave the Codex render at its shipped default,
  # not the override, closing the bug the harness scoping exists to fix.
  def test_flat_override_never_leaks_into_the_codex_toml
    File.write(File.join(@home, "config.yml"),
               "agents:\n  models:\n    plastic-executor: gpt-5.4-codex\n")

    @core.install_for_agent("codex", false)

    toml = File.read(File.join(@codex_home, "agents", "plastic-executor.toml"))
    refute_includes toml, 'model = "gpt-5.4-codex"',
      "a flat/claude-scoped literal model id must never leak into the Codex TOML"
    assert_includes toml, 'model_reasoning_effort = "medium"',
      "with no codex-scoped override, plastic-executor's shipped sonnet tier (medium effort) must pass through"
    assert_includes toml, 'model = "gpt-5.6-terra"',
      "with no codex-scoped override, plastic-executor's shipped sonnet tier model must pass through"
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

  # --- Intent 198, ACTION_4: doctor check_agent_model_drift for codex ---

  def test_codex_model_drift_passes_on_a_healthy_generated_install
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_model_drift("codex")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "pass", drift_check[:status]
  end

  def test_codex_model_drift_warns_when_a_toml_effort_disagrees_with_the_tier_default
    @core.install_for_agent("codex", false)
    default_effort = AgentModels.effort_for(AgentModels::TIER_DEFAULTS["plastic-executor"])
    wrong_effort = default_effort == "low" ? "high" : "low"
    toml_path = File.join(@codex_home, "agents", "plastic-executor.toml")
    content = File.read(toml_path).sub(
      %(model_reasoning_effort = "#{default_effort}"),
      %(model_reasoning_effort = "#{wrong_effort}")
    )
    File.write(toml_path, content)

    checks = doctor_for(@codex_home).check_agent_model_drift("codex")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "warn", drift_check[:status]
    assert drift_check[:details].any? { |d| d.include?("plastic-executor") },
      "expected drift details to name plastic-executor, got: #{drift_check[:details].inspect}"
  end

  def test_codex_model_drift_honors_a_codex_scoped_override
    File.write(File.join(@home, "config.yml"),
               "agents:\n  models:\n    codex:\n      plastic-executor: haiku\n")
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_model_drift("codex")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "pass", drift_check[:status],
      "a sanctioned codex-scoped override must never be flagged as drift"
    assert drift_check[:details].any? { |d| d.include?("plastic-executor") && d.include?("haiku") },
      "expected the sanctioned override to be LISTED, got: #{drift_check[:details].inspect}"
  end

  def test_codex_model_drift_passes_when_no_toml_files_installed
    checks = doctor_for(@codex_home).check_agent_model_drift("codex")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "pass", drift_check[:status]
  end

  # --- Intent 216: model-line drift ---

  def test_codex_model_drift_warns_when_a_toml_model_id_disagrees_with_the_tier_default
    @core.install_for_agent("codex", false)
    expected_model = AgentModels.codex_model_for(AgentModels::TIER_DEFAULTS["plastic-executor"])
    wrong_model = "gpt-5.4-mini"
    toml_path = File.join(@codex_home, "agents", "plastic-executor.toml")
    content = File.read(toml_path).sub(
      %(model = "#{expected_model}"),
      %(model = "#{wrong_model}")
    )
    File.write(toml_path, content)

    checks = doctor_for(@codex_home).check_agent_model_drift("codex")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "warn", drift_check[:status]
    detail = drift_check[:details].find do |d|
      d.include?("plastic-executor") && d.include?("model") && d.include?(wrong_model) && d.include?(expected_model)
    end
    refute_nil detail, "expected a detail line naming plastic-executor, model, #{wrong_model}, and #{expected_model}, got: #{drift_check[:details].inspect}"
    refute detail.include?("effort"), "a model-only drift must not blame the effort field, got: #{detail}"
  end

  def test_codex_model_drift_reports_both_fields_when_model_and_effort_both_drift
    @core.install_for_agent("codex", false)
    expected_model = AgentModels.codex_model_for(AgentModels::TIER_DEFAULTS["plastic-executor"])
    expected_effort = AgentModels.effort_for(AgentModels::TIER_DEFAULTS["plastic-executor"])
    wrong_model = "gpt-5.4-mini"
    wrong_effort = expected_effort == "low" ? "high" : "low"
    toml_path = File.join(@codex_home, "agents", "plastic-executor.toml")
    content = File.read(toml_path)
      .sub(%(model = "#{expected_model}"), %(model = "#{wrong_model}"))
      .sub(%(model_reasoning_effort = "#{expected_effort}"), %(model_reasoning_effort = "#{wrong_effort}"))
    File.write(toml_path, content)

    checks = doctor_for(@codex_home).check_agent_model_drift("codex")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "warn", drift_check[:status]
    detail = drift_check[:details].find { |d| d.include?("plastic-executor") }
    refute_nil detail
    assert detail.include?("model"), "expected the detail line to name the model field, got: #{detail}"
    assert detail.include?("effort"), "expected the detail line to name the effort field, got: #{detail}"
    assert detail.include?(wrong_model)
    assert detail.include?(expected_model)
    assert detail.include?(wrong_effort)
    assert detail.include?(expected_effort)
  end

  def test_codex_model_drift_honors_a_literal_codex_model_id_override
    File.write(File.join(@home, "config.yml"),
               "agents:\n  models:\n    codex:\n      plastic-executor: gpt-5.4-codex\n")
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_model_drift("codex")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "pass", drift_check[:status],
      "a literal codex model id override must never be flagged as drift"
    assert drift_check[:details].any? { |d| d.include?("plastic-executor") && d.include?("gpt-5.4-codex") },
      "expected the sanctioned literal override to be LISTED, got: #{drift_check[:details].inspect}"
  end

  def test_codex_agent_toml_model_fields_reads_both_lines_separately
    two_line = "model = \"gpt-5.6-terra\"\nmodel_reasoning_effort = \"medium\"\n"
    fields = doctor_for(@codex_home).codex_agent_toml_model_fields(two_line)

    assert_equal "gpt-5.6-terra", fields[:model]
    assert_equal "medium", fields[:effort]

    model_only = "model = \"gpt-5.4-codex\"\n"
    fields_model_only = doctor_for(@codex_home).codex_agent_toml_model_fields(model_only)

    assert_equal "gpt-5.4-codex", fields_model_only[:model]
    assert_nil fields_model_only[:effort]
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
    # home_dir (~/.codex) already exists per setup (intent 198, Decision D1:
    # that is the presence signal); hooks.json itself is what is fresh here.
    refute File.exist?(hooks_json_path), "hooks.json must be absent before install (the owner's install-day path)"

    result = @core.install_for_agent("codex", false)

    assert result[:success]
    assert File.directory?(@codex_home)
    assert File.exist?(hooks_json_path)

    data = JSON.parse(File.read(hooks_json_path))
    commands = all_codex_hook_commands(data)
    # Intent 302: the edit-path gates are gone; record is the one apply_patch hook.
    assert commands.any? { |c| c.include?("codex-hook") && c.include?("record") }
    refute commands.any? { |c| c.include?("edit-gates") || c.include?("bash-gate") }

    refute data["hooks"].key?("PreToolUse"), "no PreToolUse group may be registered (intent 302)"
    post_group = data["hooks"]["PostToolUse"].find { |g| g["matcher"] == "apply_patch" }
    refute_nil post_group, "PostToolUse must register under the apply_patch matcher"
  end

  def test_install_codex_fresh_create_writes_live_state_hook_groups
    @core.install_for_agent("codex", false)

    data = JSON.parse(File.read(hooks_json_path))
    commands = all_codex_hook_commands(data)
    %w[session-start check-update capture power-tools savepoint].each do |name|
      assert commands.any? { |c| c.include?("codex-hook") && c.include?(name) },
        "expected a codex-hook command for '#{name}', got: #{commands.inspect}"
    end

    session_group = data["hooks"]["SessionStart"]&.find { |g| g["matcher"] == "" }
    refute_nil session_group, "SessionStart must register under an empty matcher"
    prompt_group = data["hooks"]["UserPromptSubmit"]&.find { |g| g["matcher"] == "" }
    refute_nil prompt_group, "UserPromptSubmit must register under an empty matcher"
    compact_group = data["hooks"]["PreCompact"]&.find { |g| g["matcher"] == "" }
    refute_nil compact_group, "PreCompact must register under an empty matcher"
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

    refute data["hooks"]["PreToolUse"].any? { |g| g["matcher"] == "apply_patch" },
           "no Plastic apply_patch PreToolUse group may be added (intent 302)"
    plastic_group = data["hooks"]["PostToolUse"].find { |g| g["matcher"] == "apply_patch" }
    refute_nil plastic_group, "Plastic's apply_patch record group must be added alongside the user's"
  end

  def test_install_codex_is_idempotent_on_rerun
    @core.install_for_agent("codex", false)
    first = JSON.parse(File.read(hooks_json_path))

    @core.install_for_agent("codex", false)
    second = JSON.parse(File.read(hooks_json_path))

    assert_equal first, second, "re-running install must not duplicate hook groups"
    post_groups = second["hooks"]["PostToolUse"].select { |g| g["matcher"] == "apply_patch" }
    assert_equal 1, post_groups.size, "exactly one apply_patch PostToolUse group after re-run"
  end

  def test_install_codex_does_not_manifest_track_hooks_json
    @core.install_for_agent("codex", false)

    manifest = JSON.parse(File.read(File.join(@agent_dir, "plastic", "manifest.json")))
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
    # Simulate drift: drop the record command from the live file. Since intent
    # 302 the apply_patch matcher carries only this one PostToolUse command, so
    # dropping it is the way to simulate a drifted apply_patch group.
    data["hooks"]["PostToolUse"].each do |g|
      next unless g["matcher"] == "apply_patch"
      g["hooks"].reject! { |h| h["command"].include?("record") }
    end
    File.write(hooks_json_path, JSON.pretty_generate(data))

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    hooks_check = checks.find { |c| c[:name] == "codex_hooks_registered" }

    refute_nil hooks_check
    assert_equal "fail", hooks_check[:status]
    assert(hooks_check[:details].any? { |d| d.include?("record") })
  end

  # --- Intent 200: doctor codex_hooks_implemented_check (registry vs. dispatcher) ---

  def codex_hook_path
    File.join(@home, "scripts", "codex-hook")
  end

  def test_doctor_codex_hooks_implemented_passes_on_the_real_healthy_dispatcher
    @core.distribute(:install) # copies the REAL scripts/codex-hook into plastic_home
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    implemented_check = checks.find { |c| c[:name] == "codex_hooks_implemented" }

    refute_nil implemented_check
    assert_equal "pass", implemented_check[:status]
  end

  # Intent 302: the case statement carries exactly one arm, record (the edit-gates
  # arm left with the gates), followed by the trailing else. This fixture cuts the
  # record arm up to the else, so the registry names a hook the dispatcher has no
  # branch for.
  def test_doctor_codex_hooks_implemented_fails_when_a_registered_hook_has_no_dispatcher_branch
    @core.distribute(:install) # copies the REAL scripts/codex-hook into plastic_home
    @core.install_for_agent("codex", false)
    content = File.read(codex_hook_path)
    branch_start = content.index('when "record"')
    refute_nil branch_start, "fixture assumption: scripts/codex-hook must still carry a record branch"
    else_start = content.index(/^else\b/, branch_start)
    refute_nil else_start, "fixture assumption: scripts/codex-hook must still carry a trailing else"
    File.write(codex_hook_path, content[0...branch_start] + content[else_start..])

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    implemented_check = checks.find { |c| c[:name] == "codex_hooks_implemented" }

    refute_nil implemented_check
    assert_equal "fail", implemented_check[:status]
    assert(implemented_check[:details].any? { |d|
      d.include?("record") && d.include?("registered") && d.include?("allows")
    }, "expected a record detail naming the direction and the fail-open runtime effect, got: #{implemented_check[:details].inspect}")
  end

  def test_doctor_codex_hooks_implemented_fails_when_the_dispatcher_has_a_branch_nobody_registers
    @core.distribute(:install) # copies the REAL scripts/codex-hook into plastic_home
    @core.install_for_agent("codex", false)
    content = File.read(codex_hook_path)
    updated = content.sub(
      "STATE_HOOKS = %w[session-start check-update capture power-tools savepoint].freeze",
      "STATE_HOOKS = %w[session-start check-update capture power-tools savepoint phantom-gate].freeze"
    )
    refute_equal content, updated, "fixture assumption: the STATE_HOOKS literal must still match this exact text"
    File.write(codex_hook_path, updated)

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    implemented_check = checks.find { |c| c[:name] == "codex_hooks_implemented" }

    refute_nil implemented_check
    assert_equal "fail", implemented_check[:status]
    assert(implemented_check[:details].any? { |d| d.include?("phantom-gate") && d.include?("dead code") },
      "expected a phantom-gate detail naming it as dead/unreachable code, got: #{implemented_check[:details].inspect}")
  end

  def test_doctor_codex_hooks_implemented_fails_loudly_when_the_dispatcher_cannot_be_read
    @core.distribute(:install) # copies the REAL scripts/codex-hook into plastic_home
    @core.install_for_agent("codex", false)
    reshaped = <<~RUBY
      #!/usr/bin/env ruby
      # Reshaped fixture: no STATE_HOOKS constant, no `case gate`
      # statement, so the extractor must find zero names and doctor must fail
      # loudly rather than silently pass.
      GATES = {
        "code-gate" => ->(_x) { exit 0 },
        "lock-gate" => ->(_x) { exit 0 },
      }
      handler = GATES[ARGV[0]] || ->(_x) { exit(0) }
      handler.call(nil)
    RUBY
    File.write(codex_hook_path, reshaped)

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    implemented_check = checks.find { |c| c[:name] == "codex_hooks_implemented" }

    refute_nil implemented_check
    assert_equal "fail", implemented_check[:status]
    assert_includes implemented_check[:message], "Could not read"
  end

  def test_codex_dispatcher_gate_names_returns_nil_on_no_recognizable_names
    doctor = doctor_for(@codex_home)
    assert_nil doctor.codex_dispatcher_gate_names("# nothing recognizable here\nexit 0\n")
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

  # --- Intent 198, ACTION_2: doctor codex_hooks_trust advisory ---

  def test_doctor_codex_hooks_trust_advisory_present_when_hooks_registered
    @core.install_for_agent("codex", false)

    checks = doctor_for(@codex_home).check_agent_registration("codex")
    trust_check = checks.find { |c| c[:name] == "codex_hooks_trust" }

    refute_nil trust_check
    assert_equal "warn", trust_check[:status]
    assert_includes trust_check[:message], "/hooks"
  end

  def test_doctor_codex_hooks_trust_advisory_absent_when_hooks_not_registered
    checks = doctor_for(@codex_home).check_agent_registration("codex")
    trust_check = checks.find { |c| c[:name] == "codex_hooks_trust" }

    assert_nil trust_check, "no reason to remind about trust when hooks were never registered"
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

  # --- Intent 249: the INSTALLED dispatcher must reach an INSTALLED launcher ---
  #
  # scripts/codex-hook:66 resolves a live-state launcher at __dir__/../hooks/<gate>, which is
  # ~/.plastic/hooks/<gate> once installed. Before intent 249 nothing created that directory:
  # Open3.capture3 raised Errno::ENOENT, the rescue on line 72 swallowed it, and all seven
  # STATE_HOOKS silently exited 0 on every real Codex install. It went unseen because every
  # other test drives the dispatcher from the PACKAGE ROOT (test/codex_hooks_test.rb:24 pins
  # SCRIPT to the repo copy), where __dir__/../hooks is the repo's own populated hooks/. This
  # test is the one that runs from the installed layout instead.
  def test_the_installed_dispatcher_reaches_an_installed_hook_launcher
    @core.distribute(:install)

    launcher = File.join(@home, "hooks", "session-start")
    assert File.file?(launcher),
      "distribute must ship the hook launchers into <plastic_home>/hooks, or codex-hook:66 " \
      "resolves a path that does not exist and every Codex live-state hook fails open silently"

    # Stand-in launcher: a unique token on stdout and a distinctive exit code, so the assertions
    # below can tell a real relay apart from the fail-open path (empty output, exit 0).
    File.write(launcher, "#!/bin/bash\necho PLASTIC_LAUNCHER_REACHED_249\nexit 7\n")
    File.chmod(0o755, launcher)

    payload = JSON.generate({
      "session_id" => "sess-249",
      "cwd" => @home,
      "hook_event_name" => "SessionStart",
    })
    out, _err, status = Open3.capture3(
      { "RUBYOPT" => nil }, RbConfig.ruby, File.join(@home, "scripts", "codex-hook"),
      "session-start", stdin_data: payload
    )

    assert_includes out, "PLASTIC_LAUNCHER_REACHED_249",
      "the dispatcher must relay the launcher's stdout, not swallow a missing-file error"
    assert_equal 7, status.exitstatus,
      "the dispatcher must relay the launcher's exit code, not fail open with 0"
  end

  # Structural companion: every gate the dispatcher is willing to dispatch must exist and be
  # runnable after an install. The expected names are parsed out of the INSTALLED dispatcher's
  # own STATE_HOOKS declaration rather than restated here, so this cannot drift from the code.
  def test_every_state_hook_the_installed_dispatcher_names_is_installed_and_executable
    @core.distribute(:install)

    source = File.read(File.join(@home, "scripts", "codex-hook"))
    literal = source[/^STATE_HOOKS\s*=\s*%w\[([^\]]*)\]/, 1]
    refute_nil literal,
      "fixture assumption: scripts/codex-hook must still declare STATE_HOOKS as a %w[...] literal"

    names = literal.split
    assert_operator names.size, :>=, 5,
      "expected at least the five live-state hooks (intent 298 merged continue, " \
      "future-intent-check, and auto-arm into capture), got: #{names.inspect}"

    names.each do |name|
      path = File.join(@home, "hooks", name)
      assert File.file?(path),
        "STATE_HOOKS names #{name}, but <plastic_home>/hooks/#{name} was never installed"
      assert File.executable?(path),
        "<plastic_home>/hooks/#{name} is installed but not executable, so capture3 raises " \
        "EACCES and the dispatcher fails open"
    end
  end

  # Companion guard: the chmod loop over <plastic_home>/hooks/* is what repairs a launcher that
  # lost its exec bit on a PRIOR distribute. FileUtils.cp onto a NEW destination copies the
  # source's mode, so a fresh install already looks executable without the loop doing anything,
  # which lets a naive test pass even with the loop deleted. This test forces the loop to earn
  # its keep: it distributes once, strips the exec bit from an already-installed launcher (the
  # state a corrupted or manually-edited install can land in), distributes again, and asserts the
  # SECOND distribute restores 0755. It also pins that hooks.json, the registry file, is
  # deliberately left alone (spec Decision 3: a JSON registry is data, not a program).
  def test_a_second_distribute_repairs_a_launcher_that_lost_its_exec_bit
    @core.distribute(:install)

    launcher = File.join(@home, "hooks", "session-start")
    File.chmod(0o644, launcher)

    @core.distribute(:install)

    mode = File.stat(launcher).mode & 0o777
    assert_equal 0o755, mode,
      "a second distribute must restore the exec bit on hooks/session-start, or a launcher " \
      "that lost it after an earlier distribute stays broken forever: capture3 raises " \
      "Errno::EACCES, codex-hook:72 swallows it, and the live-state hook fails open silently"

    registry = File.join(@home, "hooks", "hooks.json")
    registry_mode = File.stat(registry).mode & 0o777
    refute_equal 0o755, registry_mode,
      "hooks.json is a data registry, not a program; distribute must not force it executable"
  end
end

# Intent 198, Decision D1: presence must probe home_dir (~/.codex) for an agent
# that declares one, and the install must CREATE config[:dir] (~/.agents)
# rather than demand it exist up front. These tests build their OWN
# InstallerCore instances with synthetic, minimal agent lists (never
# CodexInstallTest's shared fixture, whose @agent_dir is ALWAYS pre-created via
# Dir.mktmpdir before every test, which is exactly why this bug was never
# caught by the existing suite).
class CodexPresenceProbeTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("codex-presence-home")   # plastic_home
    @root = Dir.mktmpdir("codex-presence-root")    # holds the two harness roots
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@root)
  end

  def worktree
    File.expand_path("../../", __FILE__)
  end

  def core_for(agents)
    InstallerCore.new(package_root: worktree, plastic_home: @home, agents: agents, version: "1.0.0-test")
  end

  def test_install_succeeds_when_agents_dir_never_existed_but_codex_home_does
    agent_dir = File.join(@root, "agents-root")     # ~/.agents equivalent: NEVER created
    codex_home = File.join(@root, "codex-home")     # ~/.codex equivalent: pre-created
    FileUtils.mkdir_p(codex_home)
    refute Dir.exist?(agent_dir), "fixture precondition: the shared skills root must never have existed"
    assert Dir.exist?(codex_home), "fixture precondition: codex's own home must already exist"

    core = core_for([{ key: "codex", name: "Codex CLI", dir: agent_dir, home_dir: codex_home, flag: "--codex" }])
    result = core.install_for_agent("codex", false)

    assert result[:success], "install must succeed once codex's OWN home is present: #{result[:reason]}"
    assert Dir.exist?(agent_dir), "install must CREATE ~/.agents, not demand it exist"
    refute_empty Dir.glob(File.join(agent_dir, "skills", "plastic-*")), "skills must land under the newly-created dir"
    refute_empty Dir.glob(File.join(codex_home, "agents", "plastic-*.toml")), "agent TOMLs must be generated"
    assert File.exist?(File.join(codex_home, "hooks.json"))
    assert File.exist?(File.join(codex_home, "AGENTS.md"))
  end

  def test_failure_message_names_the_directory_actually_tested_for_codex
    agent_dir = File.join(@root, "agents-root")               # would otherwise be blamed
    absent_codex_home = File.join(@root, "codex-home-absent")  # the actual probe target; never created

    core = core_for([{ key: "codex", name: "Codex CLI", dir: agent_dir, home_dir: absent_codex_home, flag: "--codex" }])
    result = core.install_for_agent("codex", false)

    refute result[:success]
    assert_includes result[:reason], absent_codex_home
    refute_includes result[:reason], agent_dir,
      "the message must name home_dir, not the unrelated shared skills root"
  end

  def test_presence_probe_still_tests_dir_for_an_agent_with_no_home_dir
    absent_dir = File.join(@root, "claude-like-absent")  # never created; no home_dir declared

    core = core_for([{ key: "claude", name: "Claude Code", dir: absent_dir, flag: "--claude" }])
    result = core.install_for_agent("claude", false)

    refute result[:success]
    assert_includes result[:reason], absent_dir
  end
end

# Intent 198, Decision D1 (prompt_agents half): the interactive picker line
# must show the directory that actually indicates presence.
class CodexPromptAgentsLabelTest < Minitest::Test
  class FakeTTY
    def initialize(input_str) = (@io = StringIO.new(input_str))
    def tty? = true
    def gets = @io.gets
  end

  def worktree
    File.expand_path("../../", __FILE__)
  end

  def test_codex_entry_is_labeled_by_home_dir_not_the_shared_skills_root
    home = Dir.mktmpdir("prompt-agents-home")
    begin
      agents = [
        { key: "claude", name: "Claude Code", dir: "/tmp/fake-claude", flag: "--claude" },
        { key: "codex", name: "Codex CLI", dir: "/tmp/fake-agents", home_dir: "/tmp/fake-codex", flag: "--codex" },
      ]
      core = InstallerCore.new(package_root: worktree, plastic_home: home, agents: agents, version: "1.0.0-test")

      out, _err = capture_io { core.prompt_agents(input: FakeTTY.new("\n")) }

      assert_includes out, "Codex CLI (/tmp/fake-codex)"
      refute_includes out, "Codex CLI (/tmp/fake-agents)"
      assert_includes out, "Claude Code (/tmp/fake-claude)", "an agent with no home_dir must still show its dir"
    ensure
      FileUtils.rm_rf(home)
    end
  end
end
