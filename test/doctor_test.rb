require "minitest/autorun"
require "tmpdir"
require "json"
require "yaml"
require "fileutils"
require "digest"
require "open3"

require_relative "../scripts/doctor"
require_relative "../scripts/lib/installer_core"

DOCTOR_TEST_HOME = File.join(Dir.tmpdir, "plastic-doctor-test-#{Process.pid}")
DOCTOR_TEST_CLAUDE = File.join(Dir.tmpdir, "plastic-doctor-claude-#{Process.pid}")
DOCTOR_TEST_CODEX = File.join(Dir.tmpdir, "plastic-doctor-codex-#{Process.pid}")
DOCTOR_TEST_HERMES = File.join(Dir.tmpdir, "plastic-doctor-hermes-#{Process.pid}")

# Agent map pointing at throwaway tmpdirs — injected into Doctor per test.
DOCTOR_TEST_AGENTS = {
  "claude" => { name: "Claude Code", dir: DOCTOR_TEST_CLAUDE },
  "codex"  => { name: "Codex CLI",   dir: DOCTOR_TEST_CODEX },
  "hermes" => { name: "Hermes",      dir: DOCTOR_TEST_HERMES },
}.freeze

# ---------------------------------------------------------------------------
# Helpers shared across test classes
# ---------------------------------------------------------------------------

module DoctorTestHelpers
  # Fresh Doctor pointed at the test home/agents. Checks are stateless
  # (they read the filesystem), so a new instance per call is fine.
  def doctor(plastic_home: DOCTOR_TEST_HOME, agents: DOCTOR_TEST_AGENTS)
    Doctor.new(plastic_home: plastic_home, agents: agents)
  end

  # Build a minimal valid INDEX.md with all required sections
  def write_index(path, extras: "", store_refs: [])
    refs = store_refs.map { |r| "- [intent](#{r})" }.join("\n")
    content = <<~MD
      # Plastic Intent Index

      ## Active
      #{refs}

      ## Future

      ## Clusters

      ## Abandoned

      ## Completed
      #{extras}
    MD
    File.write(path, content)
  end

  # Build a valid intent directory with matching .md and frontmatter
  def write_intent(store_dir, name, frontmatter: nil)
    dir = File.join(store_dir, name)
    FileUtils.mkdir_p(dir)

    fm = frontmatter || {
      "id" => name.split("--").first,
      "intent" => "Test intent",
      "sources" => [],
      "chain" => [],
      "created" => "2026-06-01",
      "author" => "test",
      "tags" => [],
    }

    yaml_str = fm.map do |k, v|
      formatted = case v
                  when Array then v.inspect
                  when String then v.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? "'#{v}'" : v
                  else v
                  end
      "#{k}: #{formatted}"
    end.join("\n")
    # Default fixtures have empty sources/chain, so the canonical I5 ## Links
    # projection (intent 72) is the empty-state block. Using it keeps "healthy"
    # fixtures green under the graph_links_projection drift check.
    links = "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n"
    body = "## Intent\n#{name}\n\n## Context\nWhy\n\n## Outcome\nResult\n\n## Insights\nNotes\n\n#{links}"
    content = "---\n#{yaml_str}\n---\n\n#{body}"
    File.write(File.join(dir, "#{name}.md"), content)
    dir
  end

  # Build Claude hook scripts (thin wrappers), derived from HookRegistry
  # (intent 204) so fixtures always cover all 15 registered hooks, not a
  # hand-kept subset.
  def write_claude_hooks(hooks_dir)
    FileUtils.mkdir_p(hooks_dir)
    HookRegistry.claude_launcher_names.each do |hook|
      path = File.join(hooks_dir, hook)
      File.write(path, "#!/bin/bash\nexit 0\n")
      File.chmod(0o755, path)
    end
  end

  # Build a minimal but structurally real scripts/hook-edit-gates, so
  # claude_hooks_implemented_check (intent 244) has a `case gate` shape to
  # read a `when "<gate>"` label for every HookRegistry::GATE_TOOLS key,
  # matching how write_claude_hooks derives its launcher set from the
  # registry rather than a hand-kept list.
  def write_claude_dispatcher(plastic_home)
    scripts_dir = File.join(plastic_home, "scripts")
    FileUtils.mkdir_p(scripts_dir)
    whens = HookRegistry::GATE_TOOLS.keys.map { |name| "  when \"#{name}\" then nil" }.join("\n")
    path = File.join(scripts_dir, "hook-edit-gates")
    File.write(path, <<~RUBY)
      #!/usr/bin/env ruby
      def route(gate, ctx)
        case gate
      #{whens}
        end
      end
    RUBY
    File.chmod(0o755, path)
  end

  # Build a valid Claude settings.json carrying exactly the HookRegistry
  # registrations (intent 108, D7): the hooks_match_registry check compares
  # live settings against the registry, so "healthy" fixtures mirror it.
  def write_claude_settings(settings_path)
    hook_dir = File.join(File.dirname(settings_path), "hooks")
    hooks = HookRegistry.claude_settings_hooks(hook_dir: hook_dir)
                        .transform_values { |g| g.is_a?(Array) ? g : [g] }
    File.write(settings_path, JSON.pretty_generate({ "hooks" => hooks }))
  end

  # Build flat, hyphen-namespaced personal skills (plastic-<name>/SKILL.md)
  def write_skills(agent_dir)
    skill_dir = File.join(agent_dir, "skills", "plastic-doctor")
    FileUtils.mkdir_p(skill_dir)
    skill_file = File.join(skill_dir, "SKILL.md")
    File.write(skill_file, "# skill")
    track_in_agent_manifest(agent_dir, skill_file)
  end

  # Frontmatter carries the shipped TIER_DEFAULTS model so "healthy install"
  # fixtures also stay clean under the agent_model_drift check (intent 170).
  def write_agents(agent_dir)
    agents_dir = File.join(agent_dir, "agents")
    FileUtils.mkdir_p(agents_dir)
    agent_file = File.join(agents_dir, "plastic-enforcer.md")
    model = AgentModels::TIER_DEFAULTS["plastic-enforcer"]
    File.write(agent_file, "---\nname: plastic-enforcer\nmodel: #{model}\n---\n# agent\n")
    track_in_agent_manifest(agent_dir, agent_file)
  end

  # If a claude-style agent manifest already exists (<dir>/plastic/manifest.json), track
  # this file in it too, so a fixture that builds an intact install (manifest first) and
  # THEN adds skills/agents (write_skills/write_agents) stays internally consistent for
  # checks that compare installed files against the manifest (e.g. stray_skills_check,
  # intent 158a). A no-op when no manifest exists yet (most fixtures do not need one).
  def track_in_agent_manifest(agent_dir, file_path)
    manifest_path = File.join(agent_dir, "plastic", "manifest.json")
    return unless File.exist?(manifest_path)

    data = JSON.parse(File.read(manifest_path))
    data["files"] ||= {}
    data["files"][file_path] = Digest::SHA256.file(file_path).hexdigest
    File.write(manifest_path, JSON.pretty_generate(data))
  end

  # Build all required core scripts
  def write_core_scripts(scripts_dir)
    FileUtils.mkdir_p(scripts_dir)
    Doctor::REQUIRED_SCRIPTS.each do |script|
      path = File.join(scripts_dir, script)
      File.write(path, "#!/usr/bin/env ruby\n")
      File.chmod(0o755, path)
    end
  end
end

# ===========================================================================
# 1. Global Store checks
# ===========================================================================

class DoctorGlobalStoreTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    @store_dir = File.join(DOCTOR_TEST_HOME, "store")
    FileUtils.mkdir_p(@store_dir)
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
  end

  def test_valid_index_all_pass
    write_intent(@store_dir, "1a--test-intent")
    write_index(File.join(DOCTOR_TEST_HOME, "INDEX.md"), store_refs: ["store/1a--test-intent"])

    checks = doctor.check_global_store
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
    assert_equal 4, checks.size, "Should have index_exists, index_sections, orphaned_intents, ghost_references"
  end

  def test_missing_index_fails
    checks = doctor.check_global_store

    assert_equal 1, checks.size, "Should return early with one check"
    assert_equal "index_exists", checks[0][:name]
    assert_equal "fail", checks[0][:status]
    assert checks[0][:fixable]
  end

  def test_index_missing_sections_fails
    File.write(File.join(DOCTOR_TEST_HOME, "INDEX.md"), "# Plastic\n\n## Active\n\n## Future\n")

    checks = doctor.check_global_store
    sections_check = checks.find { |c| c[:name] == "index_sections" }

    assert sections_check, "index_sections check should be present"
    assert_equal "fail", sections_check[:status]
    assert_equal 3, sections_check[:details].size, "Should report 3 missing sections (Clusters, Abandoned, Completed)"
  end

  def test_orphaned_intent_warns
    write_intent(@store_dir, "1a--orphan")
    write_index(File.join(DOCTOR_TEST_HOME, "INDEX.md"))

    checks = doctor.check_global_store
    orphan_check = checks.find { |c| c[:name] == "orphaned_intents" }

    assert orphan_check, "orphaned_intents check should be present"
    assert_equal "warn", orphan_check[:status]
    assert_includes orphan_check[:details].first, "1a--orphan"
  end

  def test_ghost_reference_warns
    write_index(
      File.join(DOCTOR_TEST_HOME, "INDEX.md"),
      store_refs: ["store/99z--nonexistent"]
    )

    checks = doctor.check_global_store
    ghost_check = checks.find { |c| c[:name] == "ghost_references" }

    assert ghost_check, "ghost_references check should be present"
    assert_equal "warn", ghost_check[:status]
    assert ghost_check[:details].any? { |d| d.include?("99z--nonexistent") }
  end
end

# ===========================================================================
# 2. Convention checks
# ===========================================================================

class DoctorConventionsTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    @store_dir = File.join(DOCTOR_TEST_HOME, "store")
    FileUtils.mkdir_p(@store_dir)
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
  end

  def test_properly_named_intents_pass
    write_intent(@store_dir, "1a--valid-intent")
    write_intent(@store_dir, "2b--another-intent")

    checks = doctor.check_conventions
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All convention checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_bad_dirname_warns
    # Create a directory without the -- separator
    bad_dir = File.join(@store_dir, "no-separator")
    FileUtils.mkdir_p(bad_dir)
    File.write(File.join(bad_dir, "no-separator.md"), "# test\n")

    checks = doctor.check_conventions
    dirname_check = checks.find { |c| c[:name] == "intent_dirname" }

    assert_equal "warn", dirname_check[:status]
    assert dirname_check[:details].any? { |d| d.include?("no-separator") }
  end

  def test_missing_primary_md_warns
    dir = File.join(@store_dir, "1a--missing-file")
    FileUtils.mkdir_p(dir)
    # Write a file with a non-matching name
    File.write(File.join(dir, "wrong-name.md"), "# wrong\n")

    checks = doctor.check_conventions
    filename_check = checks.find { |c| c[:name] == "intent_filename" }

    assert_equal "warn", filename_check[:status]
    assert filename_check[:details].any? { |d| d.include?("1a--missing-file.md") }
  end

  def test_missing_frontmatter_fields_warns
    incomplete_fm = {
      "id" => "1a",
      "intent" => "Test",
      # missing: sources, chain, created, author, tags
    }
    write_intent(@store_dir, "1a--incomplete", frontmatter: incomplete_fm)

    checks = doctor.check_conventions
    fm_check = checks.find { |c| c[:name] == "frontmatter_fields" }

    assert_equal "warn", fm_check[:status]
    assert fm_check[:details].any? { |d| d.include?("sources") }
  end

  def test_frontmatter_fields_warn_is_fixable
    write_intent(@store_dir, "1a--incomplete", frontmatter: { "id" => "1a", "intent" => "x" })

    checks = doctor.check_conventions
    fm_check = checks.find { |c| c[:name] == "frontmatter_fields" }

    assert_equal "warn", fm_check[:status]
    assert_equal true, fm_check[:fixable]
    assert fm_check[:fix_hint]
    assert fm_check[:fix_hint].start_with?("Inject the missing required")
  end

  def test_frontmatter_valid_warns_on_malformed_chain
    write_intent(@store_dir, "1a--bad-chain", frontmatter: {
      "id" => "1a",
      "intent" => "x",
      "sources" => [],
      "chain" => "nope",
      "created" => "2026-06-01",
      "author" => "test",
      "tags" => [],
    })

    checks = doctor.check_conventions
    valid_check = checks.find { |c| c[:name] == "frontmatter_valid" }

    assert_equal "warn", valid_check[:status]
    assert valid_check[:details].any? { |d| d.include?("1a--bad-chain") }
    assert_equal false, valid_check[:fixable]
  end

  def test_frontmatter_valid_passes_when_well_formed
    write_intent(@store_dir, "1a--valid-intent")

    checks = doctor.check_conventions
    valid_check = checks.find { |c| c[:name] == "frontmatter_valid" }

    assert_equal "pass", valid_check[:status]
  end

  def test_required_fields_are_a_single_source
    # Doctor must not keep its own copy of the required-field list; it aliases
    # IntentValidator::REQUIRED_FIELDS so the two can never drift (intent 60).
    assert_equal IntentValidator::REQUIRED_FIELDS, Doctor::REQUIRED_FRONTMATTER_FIELDS
  end
end

# ===========================================================================
# Intent-126 regressions: lock in two already-shipped first-run fixes so they
# cannot silently regress. Neither test reuses write_intent's date-quoting or
# a pre-filtered directory listing; each drives the real code path.
# ===========================================================================

class Doctor126RegressionTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    @store_dir = File.join(DOCTOR_TEST_HOME, "store")
    FileUtils.mkdir_p(@store_dir)
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
  end

  # Ruby 4 Psych raises DisallowedClass on an unquoted `created:` date unless
  # parse_frontmatter passes `permitted_classes: [Date, Time]` to safe_load.
  # write_intent quotes the date (see the helper above), which would hide this
  # regression, so this test writes the frontmatter by hand instead.
  def test_unquoted_created_date_parses_to_a_date_and_is_not_missing_frontmatter
    dir = File.join(@store_dir, "1a--unquoted-date")
    FileUtils.mkdir_p(dir)
    content = <<~MD
      ---
      id: 1a
      intent: Test intent
      sources: []
      chain: []
      created: 2026-06-01
      author: test
      tags: []
      ---

      ## Intent
      1a--unquoted-date

      ## Context
      Why

      ## Outcome
      Result

      ## Insights
      Notes

      ## Links
      <!-- No sources or chain; this intent has no graph edges to project. -->
    MD
    md_path = File.join(dir, "1a--unquoted-date.md")
    File.write(md_path, content)

    fm = doctor.parse_frontmatter(md_path)

    refute_nil fm, "parse_frontmatter must not return nil for valid unquoted-date frontmatter"
    assert_kind_of Date, fm["created"], "created: should parse as a real Date, not a String or nil"

    checks = doctor.check_conventions
    fm_check = checks.find { |c| c[:name] == "frontmatter_fields" }
    assert_equal "pass", fm_check[:status],
      "frontmatter must not be misreported as missing: #{fm_check[:details]}"
  end

  # .obsidian / .git dot-directories alongside real intents used to be walked
  # as intents, producing false orphaned/malformed-frontmatter noise for
  # newcomers. store_intent_dirs must reject dot-entries.
  def test_dot_directories_excluded_from_intent_scanning
    write_intent(@store_dir, "1a--valid-intent")
    FileUtils.mkdir_p(File.join(@store_dir, ".obsidian"))
    File.write(File.join(@store_dir, ".obsidian", "workspace.json"), "{}")
    FileUtils.mkdir_p(File.join(@store_dir, ".git"))
    File.write(File.join(@store_dir, ".git", "HEAD"), "ref: refs/heads/main\n")

    entries = doctor.store_intent_dirs(@store_dir)
    assert_equal ["1a--valid-intent"], entries

    write_index(File.join(DOCTOR_TEST_HOME, "INDEX.md"), store_refs: ["store/1a--valid-intent"])

    global_checks = doctor.check_global_store
    orphan_check = global_checks.find { |c| c[:name] == "orphaned_intents" }
    assert_equal "pass", orphan_check[:status]
    assert orphan_check[:details].none? { |d| d.include?(".obsidian") || d.include?(".git") }

    convention_checks = doctor.check_conventions
    dirname_check = convention_checks.find { |c| c[:name] == "intent_dirname" }
    assert_equal "pass", dirname_check[:status]
    assert dirname_check[:details].none? { |d| d.include?(".obsidian") || d.include?(".git") }
  end
end

# ===========================================================================
# Intent-51 regression: an intent born without `chain` (intent 60).
# Intent 51 was created with no `chain` key and nothing caught it at birth.
# This reproduces that case across all three detection paths: the library, the
# validate-intent CLI, and doctor (which marks it repairable via fix_hint).
# ===========================================================================

class Intent51RegressionTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    @store_dir = File.join(DOCTOR_TEST_HOME, "store")
    FileUtils.mkdir_p(@store_dir)
    # An intent written WITHOUT a chain key, exactly the intent-51 failure.
    write_intent(@store_dir, "51--chainless", frontmatter: {
      "id" => "51",
      "intent" => "born without chain",
      "sources" => [],
      "created" => "2026-06-01",
      "author" => "test",
      "tags" => [],
    })
    @intent_dir = File.join(@store_dir, "51--chainless")
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
  end

  def test_library_flags_chainless_intent
    result = IntentValidator.validate(@intent_dir)

    refute result[:ok]
    assert_includes result[:missing], "chain"
  end

  def test_cli_exits_non_zero_for_chainless_intent
    cli = File.expand_path("../scripts/validate-intent", __dir__)
    ok = system(cli, @intent_dir, out: File::NULL, err: File::NULL)

    refute ok, "validate-intent must exit non-zero for an intent missing chain"
  end

  def test_doctor_flags_chainless_intent_as_fixable
    checks = doctor.check_conventions
    fm_check = checks.find { |c| c[:name] == "frontmatter_fields" }

    assert_equal "warn", fm_check[:status]
    assert_equal true, fm_check[:fixable]
    assert fm_check[:details].any? { |d| d.include?("51--chainless") && d.include?("chain") }
  end
end

# ===========================================================================
# 3. Agent Registration checks (Claude)
# ===========================================================================

class DoctorAgentRegistrationTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.rm_rf(DOCTOR_TEST_CLAUDE)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_CLAUDE)
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.rm_rf(DOCTOR_TEST_CLAUDE)
  end

  def test_all_hooks_present_and_executable_pass
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    # A real install ships a manifest.json before anything is tracked into
    # it; without one here, stray_skills (intent 276) correctly warns that
    # skill ownership cannot be verified.
    agent_manifest = File.join(DOCTOR_TEST_CLAUDE, "plastic", "manifest.json")
    FileUtils.mkdir_p(File.dirname(agent_manifest))
    File.write(agent_manifest, JSON.pretty_generate({ "files" => {} }))

    write_claude_hooks(hooks_dir)
    write_claude_dispatcher(DOCTOR_TEST_HOME)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    write_agents(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_missing_hook_scripts_fails
    # Create hooks dir but only write some hooks
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    FileUtils.mkdir_p(hooks_dir)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    hooks_check = checks.find { |c| c[:name] == "hooks_exist" }

    assert_equal "fail", hooks_check[:status]
    assert_equal HookRegistry.claude_launcher_names.size, hooks_check[:details].size
  end

  def test_non_executable_hooks_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    FileUtils.mkdir_p(hooks_dir)
    # Write hooks but don't make them executable
    HookRegistry.claude_launcher_names.each do |hook|
      path = File.join(hooks_dir, hook)
      File.write(path, "#!/bin/bash\nexit 0\n")
      File.chmod(0o644, path)
    end
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    exec_check = checks.find { |c| c[:name] == "hooks_executable" }

    assert_equal "fail", exec_check[:status]
    assert_equal HookRegistry.claude_launcher_names.size, exec_check[:details].size
  end

  def test_missing_settings_entries_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_skills(DOCTOR_TEST_CLAUDE)
    # Write settings without any hooks
    File.write(File.join(DOCTOR_TEST_CLAUDE, "settings.json"), JSON.pretty_generate({ "hooks" => {} }))

    checks = doctor.check_agent_registration("claude")
    registered_check = checks.find { |c| c[:name] == "hooks_registered" }

    assert_equal "fail", registered_check[:status]
    assert_equal Doctor::CLAUDE_HOOK_EVENTS.size, registered_check[:details].size
  end

  def test_missing_settings_json_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_skills(DOCTOR_TEST_CLAUDE)
    # No settings.json at all

    checks = doctor.check_agent_registration("claude")
    registered_check = checks.find { |c| c[:name] == "hooks_registered" }

    assert_equal "fail", registered_check[:status]
  end

  # --- hooks_match_registry (intent 108, D7) ---------------------------------

  def test_registry_shaped_settings_pass_hooks_match_registry
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    refute_nil registry_check, "agent_registration must include hooks_match_registry"
    assert_equal "pass", registry_check[:status]
  end

  def test_settings_missing_the_bash_group_fail_hooks_match_registry
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    # Drop the bash-gate group: the exact divergence that shipped it dead.
    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["PreToolUse"].reject! { |g| g["matcher"] == "Bash" }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    assert_equal "fail", registry_check[:status]
    assert registry_check[:details].any? { |d| d.include?("bash-gate") },
           "the diff must name the missing bash-gate: #{registry_check[:details].inspect}"
  end

  # intent 115 (AC1): a foreign tool (Serena) occupies the FIRST SessionStart
  # matcher-"" group and the Plastic hooks live in a SECOND matcher-"" group.
  # A single-group Array#find masks the real hooks; aggregation across ALL
  # same-matcher groups must PASS. RED before the fix, GREEN after.
  def test_shared_matcher_foreign_first_group_passes
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    # Prepend a foreign matcher-"" group whose command is NOT plastic- (so it
    # is not mistaken for a stray); the Plastic hooks stay in the second group.
    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].unshift({
      "matcher" => "",
      "hooks" => [{ "type" => "command", "command" => "/opt/serena/hooks/serena-session-start" }],
    })
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    assert_equal "pass", registry_check[:status],
                 "shared matcher with a foreign first group must pass: #{registry_check[:details].inspect}"
  end

  # intent 115 (AC2): when a Plastic hook is absent from EVERY live group with
  # that matcher, the check must still FAIL and name the missing command.
  def test_shared_matcher_all_groups_missing_plastic_hook_fails
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    # Remove plastic-check-update from every SessionStart group, then prepend a
    # foreign group: the hook is now missing from all same-matcher groups.
    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].each do |g|
      g["hooks"].reject! { |h| h["command"].to_s.end_with?("plastic-check-update") }
    end
    settings["hooks"]["SessionStart"].unshift({
      "matcher" => "",
      "hooks" => [{ "type" => "command", "command" => "/opt/serena/hooks/serena-session-start" }],
    })
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    assert_equal "fail", registry_check[:status]
    assert registry_check[:details].any? { |d| d.include?("plastic-check-update") },
           "the diff must name the missing plastic-check-update: #{registry_check[:details].inspect}"
  end

  # --- shape tolerance on hand-edited settings.json (review finding, 276) --
  # settings.json is hand-editable, so "hooks" (or any nested value) need
  # not be the Hash shape HookRegistry always emits. Before this fix,
  # hooks_match_registry raised TypeError (String has no #dig) as soon as
  # "hooks" itself was not a Hash.

  def test_hooks_match_registry_survives_a_non_hash_hooks_value
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_skills(DOCTOR_TEST_CLAUDE)
    File.write(File.join(DOCTOR_TEST_CLAUDE, "settings.json"),
               JSON.pretty_generate({ "hooks" => "not-a-hash" }))

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    refute_nil registry_check
    assert_equal "fail", registry_check[:status],
                 "nothing is registered, so this must fail cleanly rather than raise"
  end

  # Before this fix, a per-event value that is not an Array raised
  # NoMethodError (String has no #select) inside live.select.
  def test_hooks_match_registry_survives_a_non_array_event_value
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_skills(DOCTOR_TEST_CLAUDE)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"] = "not-an-array"
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    refute_nil registry_check
    assert_equal "fail", registry_check[:status]
  end

  # Before this fix, a non-Hash entry inside a live hook group's "hooks"
  # array raised NoMethodError (nil has no #[]) inside the got computation.
  def test_hooks_match_registry_survives_a_non_hash_hook_entry
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_skills(DOCTOR_TEST_CLAUDE)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << nil
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    refute_nil registry_check
    assert_equal "pass", registry_check[:status],
                 "the stray nil entry adds nothing and removes nothing already matching; this must not raise"
  end

  # each_hook_command (shared by hooks_entries_owned_check and the Codex
  # sibling) walks the same hand-editable data; it must not raise either.
  def test_hooks_entries_owned_survives_a_non_hash_hooks_value
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_skills(DOCTOR_TEST_CLAUDE)
    File.write(File.join(DOCTOR_TEST_CLAUDE, "settings.json"),
               JSON.pretty_generate({ "hooks" => "not-a-hash" }))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    refute_nil owned_check
    assert_equal "pass", owned_check[:status],
                 "nothing to walk, so this must report pass rather than raise"
  end

  # --- launcher_path_from_command shape-aware resolution (review round 2) --
  # A whitespace split treated a fragment of the real path as the whole
  # path, so a hooks dir containing a space made every registered launcher
  # report a false "missing launcher" fail forever (the remedy re-runs the
  # installer, which rewrites the same spaced path).

  def test_hooks_entries_owned_passes_with_a_spaced_hooks_dir_when_launcher_present
    base = Dir.mktmpdir("plastic-doctor-claude-base")
    claude_dir = File.join(base, "my plastic home")
    FileUtils.mkdir_p(claude_dir)
    hooks_dir = File.join(claude_dir, "hooks")
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(claude_dir, "settings.json"))
    write_skills(claude_dir)

    d = Doctor.new(plastic_home: DOCTOR_TEST_HOME, agents: { "claude" => { name: "Claude Code", dir: claude_dir } })
    checks = d.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "pass", owned_check[:status],
                 "a spaced hooks dir with the launcher present must not report it missing: #{Array(owned_check[:details]).inspect}"
  ensure
    FileUtils.rm_rf(base) if base
  end

  def test_hooks_entries_owned_fails_with_a_spaced_hooks_dir_when_launcher_absent
    base = Dir.mktmpdir("plastic-doctor-claude-base")
    claude_dir = File.join(base, "my plastic home")
    FileUtils.mkdir_p(claude_dir)
    hooks_dir = File.join(claude_dir, "hooks")
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(claude_dir, "settings.json"))
    write_skills(claude_dir)
    File.delete(File.join(hooks_dir, "plastic-session-start"))

    d = Doctor.new(plastic_home: DOCTOR_TEST_HOME, agents: { "claude" => { name: "Claude Code", dir: claude_dir } })
    checks = d.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "fail", owned_check[:status]
    details = Array(owned_check[:details])
    assert_equal 1, details.size, "only the deleted launcher must be reported missing: #{details.inspect}"
    assert_includes details.first, "plastic-session-start"
    refute details.any? { |d| d.include?("plastic-check-update") },
           "a launcher that is still present must never be named missing: #{details.inspect}"
  ensure
    FileUtils.rm_rf(base) if base
  end

  # Item 2 BLOCKING (round 3): a real apostrophe inside the hooks dir must
  # never be treated as a quote delimiter and deleted -- that turned
  # "o'brien" into "obrien", a directory that does not exist.
  def test_hooks_entries_owned_passes_with_an_apostrophe_in_the_hooks_dir_when_launcher_present
    base = Dir.mktmpdir("plastic-doctor-claude-apos-base")
    claude_dir = File.join(base, "o'brien plastic home")
    FileUtils.mkdir_p(claude_dir)
    hooks_dir = File.join(claude_dir, "hooks")
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(claude_dir, "settings.json"))
    write_skills(claude_dir)

    d = Doctor.new(plastic_home: DOCTOR_TEST_HOME, agents: { "claude" => { name: "Claude Code", dir: claude_dir } })
    checks = d.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "pass", owned_check[:status],
                 "an apostrophe in the hooks dir must not report the launcher missing: #{Array(owned_check[:details]).inspect}"
  ensure
    FileUtils.rm_rf(base) if base
  end

  # --- unowned_prefixed_command? on a spaced path (round 3) ----------------
  # The 32b survivor shape (a real user hook sharing the plastic- prefix)
  # must still warn even when its own path contains a space; the executable
  # candidate machinery must not truncate it to a fragment's basename.
  def test_spaced_user_hook_still_warns_hooks_entries_owned
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    spaced_dir = File.join(DOCTOR_TEST_CLAUDE, "my tools")
    FileUtils.mkdir_p(spaced_dir)
    user_hook = File.join(spaced_dir, "plastic-writing-style")
    File.write(user_hook, "#!/bin/bash\nexit 0\n")
    File.chmod(0o755, user_hook)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => user_hook,
    }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "warn", owned_check[:status],
                 "a spaced user hook must still warn as a naming collision: #{Array(owned_check[:details]).inspect}"
    assert Array(owned_check[:details]).any? { |d| d.include?("reserved prefix") }
  end

  # --- silence-where-fail-is-correct shapes (item 4) -----------------------
  # A trailing argument, a quoted argument, and a leading interpreter flag
  # must never mask a genuinely missing launcher -- the candidate search
  # anchors on the launcher NAME's occurrence, so what comes after it (an
  # argument) or before it (an interpreter word) must not change the
  # verdict when the launcher itself is gone.

  def test_hooks_entries_owned_fails_when_a_trailing_flag_command_is_missing
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)
    launcher_path = File.join(hooks_dir, "plastic-session-start")
    File.delete(launcher_path)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"].first["command"] = "#{launcher_path} --verbose"
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "fail", owned_check[:status]
    assert Array(owned_check[:details]).any? { |d| d.include?("missing launcher") }
  end

  def test_hooks_entries_owned_fails_when_a_quoted_argument_command_is_missing
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)
    launcher_path = File.join(hooks_dir, "plastic-session-start")
    File.delete(launcher_path)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"].first["command"] = "#{launcher_path} --msg \"hello world\""
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "fail", owned_check[:status]
    assert Array(owned_check[:details]).any? { |d| d.include?("missing launcher") }
  end

  def test_hooks_entries_owned_fails_when_a_ruby_flag_command_is_missing
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)
    launcher_path = File.join(hooks_dir, "plastic-session-start")
    File.delete(launcher_path)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"].first["command"] = "ruby -W0 #{launcher_path}"
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "fail", owned_check[:status]
    assert Array(owned_check[:details]).any? { |d| d.include?("missing launcher") }
  end

  # Item 5 (round 3): HookRegistry.claude_settings_hooks itself, not the
  # write_claude_settings test helper's .transform_values normalization,
  # returns a bare Hash (not a one-element Array) for any event with
  # exactly one matcher group -- the shape that broke the outer
  # Array(groups) call in each_hook_command.
  def test_hooks_entries_owned_walks_the_raw_registry_single_group_hash_shape
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_skills(DOCTOR_TEST_CLAUDE)

    raw_hooks = HookRegistry.claude_settings_hooks(hook_dir: hooks_dir)
    assert raw_hooks["SessionStart"].is_a?(Hash),
           "fixture precondition: SessionStart must be the single-group bare-Hash shape"
    File.write(File.join(DOCTOR_TEST_CLAUDE, "settings.json"), JSON.pretty_generate({ "hooks" => raw_hooks }))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }
    assert_equal "pass", owned_check[:status],
                 "the raw single-group registry shape must still be walked: #{Array(owned_check[:details]).inspect}"

    File.delete(File.join(hooks_dir, "plastic-session-start"))
    checks2 = doctor.check_agent_registration("claude")
    owned_check2 = checks2.find { |c| c[:name] == "hooks_entries_owned" }
    assert_equal "fail", owned_check2[:status],
                 "a SessionStart-group launcher deletion must be detected through the raw Hash shape"
  end

  # --- unowned_prefixed_command? scans only the executable token ----------
  # A third-party command whose ARGUMENT merely carries a plastic- token
  # must stay silent: it names no hook of anyone's, and warning here told
  # the owner to rename a hook that does not exist.
  def test_argument_only_plastic_token_is_not_flagged_by_hooks_entries_owned
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => "/opt/tools/my-linter --profile plastic-strict",
    }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "pass", owned_check[:status],
                 "an argument-only plastic- token must not warn: #{Array(owned_check[:details]).inspect}"
    assert_empty Array(owned_check[:details])
  end

  # --- each_hook_command shape tolerance (review round 2) -----------------

  # A hand-edit that drops the array wrapper around a single hook entry
  # (a bare Hash instead of a one-element Array) must not make the whole
  # group invisible to this check.
  def test_hooks_entries_owned_walks_a_hash_shaped_hooks_group
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"] = [{
      "matcher" => "",
      "hooks" => { "type" => "command", "command" => File.join(hooks_dir, "plastic-writing-style") },
    }]
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "warn", owned_check[:status],
                 "a Hash-shaped hooks group must still be walked, not silently skipped"
    assert Array(owned_check[:details]).any? { |d| d.include?("reserved prefix") }
  end

  # A relative command path is never resolved against the doctor process's
  # own CWD -- it is left untested, never reported missing.
  def test_hooks_entries_owned_does_not_fail_a_relative_command_path
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"].first["command"] = "hooks/plastic-session-start"
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "pass", owned_check[:status],
                 "a relative command path must be silence, not a false missing-launcher fail: #{Array(owned_check[:details]).inspect}"
  end

  # intent 115 (AC3): a stray Plastic hook the registry does not define must
  # still be reported. Stray detection is untouched by the aggregation fix.
  #
  # Intent 275 note: the fixture command changed from an invented
  # "plastic-bogus-hook" to the real retired launcher "plastic-lock-gate".
  # Stray detection now runs through HookRegistry.claude_purge_command? (the
  # same registry-membership test the installer purge uses), and an invented
  # name that Plastic never registered is -- correctly, per Decision 2's
  # forgotten-retirement tradeoff -- now indistinguishable from a foreign
  # hook, not a stray. A RETIRED name is still recognised as ours by the
  # registry while absent from the current expected set, which is exactly
  # the drift AC3 means to catch.
  def test_stray_plastic_hook_still_reported
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => "/opt/plastic/hooks/plastic-lock-gate"
    }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    assert_equal "fail", registry_check[:status]
    assert registry_check[:details].any? { |d| d.include?("stray") && d.include?("plastic-lock-gate") },
           "the diff must report the stray plastic hook: #{registry_check[:details].inspect}"
  end

  # Intent 275 regression: hooks_match_registry and hooks_registered used a
  # bare `cmd.include?("plastic-")` ownership test, the same substring bug the
  # installer purge carried. A user-owned SessionStart hook that merely shares
  # the plastic- prefix (the exact 32b shape) must never be treated as a
  # Plastic registration by either check.
  #
  # The fixture is built with write_claude_settings (HookRegistry.claude_settings_hooks
  # against DOCTOR_TEST_CLAUDE's own hooks dir), then the user hook is added
  # alongside it in the same SessionStart group -- exactly the shape the FIXED
  # merge_claude_hooks leaves behind (pinned directly by
  # test_user_plastic_prefixed_hook_in_matching_group_is_not_clobbered in
  # install_hooks_test.rb). merge_claude_hooks itself is not called here: it
  # hardcodes hook_dir to the real Dir.home, not an injectable agent dir, so
  # driving it directly would write real-$HOME paths into this tmpdir fixture
  # and produce a false mismatch against DOCTOR_TEST_CLAUDE's expected paths.
  def test_user_plastic_prefixed_hook_is_not_a_stray_after_a_real_merge
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => "~/.claude/hooks/plastic-writing-style"
    }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    registry_check = checks.find { |c| c[:name] == "hooks_match_registry" }

    assert_equal "pass", registry_check[:status],
                 "a user hook sharing the plastic- prefix must not register as a stray: #{Array(registry_check[:details]).inspect}"
    assert(Array(registry_check[:details]).none? { |d| d.include?("plastic-writing-style") })
  end

  # The other half of the same regression: a settings.json carrying ONLY a
  # user-owned plastic-prefixed hook (no real Plastic registration at all)
  # must NOT satisfy hooks_registered for that event. Before the fix, the
  # substring test let the user hook count as "Plastic is registered here".
  def test_hooks_registered_does_not_count_a_lone_user_plastic_prefixed_hook
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_skills(DOCTOR_TEST_CLAUDE)

    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    File.write(settings_path, JSON.pretty_generate({
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [
            { "type" => "command", "command" => "~/.claude/hooks/plastic-writing-style" },
          ] },
        ],
      },
    }))

    checks = doctor.check_agent_registration("claude")
    registered_check = checks.find { |c| c[:name] == "hooks_registered" }

    assert_equal "fail", registered_check[:status]
    assert_includes registered_check[:details], "SessionStart",
                     "a lone user hook must not satisfy the SessionStart requirement: #{registered_check[:details].inspect}"
  end

  # Intent 277: the other half of ownership. 275 moved this check off the
  # `plastic-` substring and onto HookRegistry.claude_purge_command?, whose set
  # is current PLUS retired PLUS non-hook launchers, because that is what the
  # installer's purge needs. A liveness check needs the narrower question: a
  # SessionStart carrying only plastic-lock-gate (retired with intent 244) has
  # nothing left on disk to run, so the event is not registered.
  def test_hooks_registered_does_not_count_a_lone_retired_launcher
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_skills(DOCTOR_TEST_CLAUDE)

    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    File.write(settings_path, JSON.pretty_generate({
      "hooks" => {
        "SessionStart" => [
          { "matcher" => "", "hooks" => [
            { "type" => "command", "command" => "/opt/plastic/hooks/plastic-lock-gate" },
          ] },
        ],
      },
    }))

    checks = doctor.check_agent_registration("claude")
    registered_check = checks.find { |c| c[:name] == "hooks_registered" }

    assert_equal "fail", registered_check[:status]
    details = Array(registered_check[:details])
    assert details.any? { |d| d.include?("SessionStart") },
           "a lone retired launcher must not satisfy the SessionStart requirement: #{details.inspect}"
    assert details.any? { |d| d.include?("plastic-lock-gate") },
           "the failure must name the retired launcher it found: #{details.inspect}"
  end

  # The pass side of the same predicate, which nothing pinned before intent 277:
  # a settings.json carrying the registrations HookRegistry defines today must
  # satisfy every required event.
  def test_hooks_registered_passes_on_a_full_current_registration
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    registered_check = checks.find { |c| c[:name] == "hooks_registered" }

    assert_equal "pass", registered_check[:status],
                 "current registrations must satisfy the check: #{Array(registered_check[:details]).inspect}"
  end

  # --- hooks_entries_owned (intent 276) --------------------------------------
  # hooks_registered and hooks_match_registry both filter settings.json
  # commands through an ownership predicate before comparing, so a command
  # that fails the predicate never enters either comparison. This check walks
  # every command unfiltered and reports the two modes that gap hides.

  def test_hooks_entries_owned_passes_on_a_clean_install
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    refute_nil owned_check, "agent_registration must include hooks_entries_owned"
    assert_equal "pass", owned_check[:status]
    assert_empty Array(owned_check[:details])
  end

  # The intent 32b survivor shape and the owner ruling's headline case: a user
  # hook that merely shares the plastic- prefix, never registered by Plastic,
  # warns as a naming collision — never reported as a missing launcher.
  def test_unowned_plastic_prefixed_entry_warns_hooks_entries_owned
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => File.join(hooks_dir, "plastic-writing-style"),
    }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "warn", owned_check[:status]
    details = Array(owned_check[:details])
    assert_equal 1, details.size
    assert details.first.include?("reserved prefix"), "expected a reserved-prefix detail: #{details.inspect}"
    refute details.any? { |d| d.include?("missing launcher") },
           "a naming collision must not be reported as a missing launcher: #{details.inspect}"
  end

  def test_registered_launcher_missing_from_disk_fails_hooks_entries_owned
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    File.delete(File.join(hooks_dir, "plastic-session-start"))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "fail", owned_check[:status]
    details = Array(owned_check[:details])
    assert_equal 1, details.size
    assert details.first.include?("missing launcher"), "expected a missing-launcher detail: #{details.inspect}"
    assert_includes details.first, "plastic-session-start"
  end

  def test_hooks_entries_owned_reports_both_modes_distinctly
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)
    File.delete(File.join(hooks_dir, "plastic-session-start"))

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => File.join(hooks_dir, "plastic-writing-style"),
    }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "fail", owned_check[:status]
    details = Array(owned_check[:details])
    assert_equal 2, details.size
    assert details.any? { |d| d.include?("reserved prefix") }, "missing the reserved-prefix detail: #{details.inspect}"
    assert details.any? { |d| d.include?("missing launcher") }, "missing the missing-launcher detail: #{details.inspect}"
  end

  def test_third_party_hook_entry_is_not_flagged_by_hooks_entries_owned
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => "~/bin/my-linter",
    }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "pass", owned_check[:status]
    assert_empty Array(owned_check[:details])
  end

  def test_retired_launcher_entry_is_not_flagged_by_hooks_entries_owned
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    settings_path = File.join(DOCTOR_TEST_CLAUDE, "settings.json")
    write_claude_settings(settings_path)
    write_skills(DOCTOR_TEST_CLAUDE)

    settings = JSON.parse(File.read(settings_path))
    settings["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => "/opt/plastic/hooks/plastic-lock-gate",
    }
    File.write(settings_path, JSON.pretty_generate(settings))

    checks = doctor.check_agent_registration("claude")
    owned_check = checks.find { |c| c[:name] == "hooks_entries_owned" }

    assert_equal "pass", owned_check[:status],
                 "a retired launcher belongs to hooks_match_registry, not hooks_entries_owned: #{Array(owned_check[:details]).inspect}"
    assert_empty Array(owned_check[:details])
  end

  def test_missing_skills_directory_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    # No skills directory

    checks = doctor.check_agent_registration("claude")
    skills_check = checks.find { |c| c[:name] == "skills_exist" }

    assert_equal "fail", skills_check[:status]
  end

  def test_missing_agents_directory_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    # No agents directory

    checks = doctor.check_agent_registration("claude")
    agents_check = checks.find { |c| c[:name] == "agents_exist" }

    refute_nil agents_check, "agent_registration must include an agents_exist check"
    assert_equal "fail", agents_check[:status]
  end

  def test_installed_agents_pass
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    write_agents(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    agents_check = checks.find { |c| c[:name] == "agents_exist" }

    assert_equal "pass", agents_check[:status]
  end

  def test_missing_agent_dir_fails
    FileUtils.rm_rf(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")

    assert_equal 1, checks.size
    assert_equal "agent_dir_exists", checks[0][:name]
    assert_equal "fail", checks[0][:status]
  end

  # --- hooks_exist / hooks_no_orphans derive from HookRegistry, not a
  # hand-kept list (intent 204) ---

  # Under the old hand-kept CLAUDE_HOOK_SCRIPTS (7 names) this launcher was
  # never inspected, so a missing gate launcher would have gone unnoticed.
  # The derived set covers everything HookRegistry.events registers, so this
  # still fails. Intent 244 collapsed the five edit-path gates into one
  # registered launcher, edit-gates, which is now the launcher this test
  # deletes to prove the derived check still catches a missing one.
  def test_missing_previously_unchecked_gate_launcher_fails_hooks_exist
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    File.delete(File.join(hooks_dir, "plastic-edit-gates"))
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    hooks_check = checks.find { |c| c[:name] == "hooks_exist" }

    assert_equal "fail", hooks_check[:status]
    assert_includes hooks_check[:details].join, "plastic-edit-gates"
  end

  def test_orphan_launcher_not_in_registry_fails_hooks_no_orphans
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    bogus = File.join(hooks_dir, "plastic-bogus-gate")
    File.write(bogus, "#!/bin/bash\nexit 0\n")
    File.chmod(0o755, bogus)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    orphan_check = checks.find { |c| c[:name] == "hooks_no_orphans" }

    assert_equal "warn", orphan_check[:status]
    assert_includes orphan_check[:details].join, "plastic-bogus-gate"
  end

  def test_statusline_launcher_not_flagged_as_orphan
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    statusline = File.join(hooks_dir, "plastic-statusline")
    File.write(statusline, "#!/bin/bash\nexit 0\n")
    File.chmod(0o755, statusline)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    orphan_check = checks.find { |c| c[:name] == "hooks_no_orphans" }

    assert_equal "pass", orphan_check[:status],
                 "plastic-statusline is the statusLine entry point, not a hook: #{orphan_check[:details].inspect}"
  end

  def test_all_launchers_plus_statusline_pass_hooks_exist_and_no_orphans
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    statusline = File.join(hooks_dir, "plastic-statusline")
    File.write(statusline, "#!/bin/bash\nexit 0\n")
    File.chmod(0o755, statusline)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    write_agents(DOCTOR_TEST_CLAUDE)

    checks = doctor.check_agent_registration("claude")
    hooks_check = checks.find { |c| c[:name] == "hooks_exist" }
    exec_check = checks.find { |c| c[:name] == "hooks_executable" }
    orphan_check = checks.find { |c| c[:name] == "hooks_no_orphans" }

    # Intent 244 collapsed the five edit-path gates (code-gate, lock-gate,
    # savepoint-pre, links-gate, create-gate) into one registered launcher,
    # edit-gates: 14 - 5 + 1 = 10.
    assert_equal 10, HookRegistry.claude_launcher_names.size
    assert_equal "pass", hooks_check[:status]
    assert_equal "pass", exec_check[:status]
    assert_equal "pass", orphan_check[:status]
  end
end

# ===========================================================================
# 2a. codex_hooks_entries_owned (intent 276): the Codex sibling of
# hooks_entries_owned. Codex has no per-launcher files, so mode (b) collapses
# to "our dispatcher is registered but scripts/codex-hook is not on disk", and
# mode (a) is the same reserved-prefix scan over tokens. DOCTOR_TEST_AGENTS
# carries no home_dir for codex (see intent 33a), so this class builds its own
# Doctor per codex_install_test.rb's doctor_for pattern rather than the shared
# `doctor()` helper.
# ===========================================================================

class DoctorCodexHooksEntriesOwnedTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    @home = Dir.mktmpdir("codex-owned-home")
    @agent_dir = Dir.mktmpdir("codex-owned-agents")
    @codex_home = File.join(@home, "codex-home")
    FileUtils.mkdir_p(@codex_home)
    @dispatcher_path = File.join(@home, "scripts", "codex-hook")
    FileUtils.mkdir_p(File.dirname(@dispatcher_path))
    File.write(@dispatcher_path, "#!/usr/bin/env ruby\n")
    File.chmod(0o755, @dispatcher_path)
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@agent_dir)
  end

  # Undetectable-but-fail-open runner (matches codex_install_test.rb): no real
  # `codex` binary dependency, and the version-floor check this exercises
  # incidentally is not what these tests are about.
  def doctor_for
    Doctor.new(plastic_home: @home,
               agents: { "codex" => { name: "Codex CLI", dir: @agent_dir, home_dir: @codex_home } },
               runner: ->(_args) { ["", false] })
  end

  def owned_check
    doctor_for.check_codex_registration("codex", @agent_dir)
              .find { |c| c[:name] == "codex_hooks_entries_owned" }
  end

  def write_hooks_json
    hooks = HookRegistry.codex_hooks_json(dispatcher_path: @dispatcher_path)
    File.write(File.join(@codex_home, "hooks.json"), JSON.pretty_generate({ "hooks" => hooks }))
  end

  def test_codex_hooks_entries_owned_passes_on_a_clean_install
    write_hooks_json

    check = owned_check
    refute_nil check, "codex registration must include codex_hooks_entries_owned"
    assert_equal "pass", check[:status]
    assert_empty Array(check[:details])
  end

  # Shape tolerance (review finding, 276): hooks.json is hand-editable too;
  # each_hook_command must not raise when "hooks" is not a Hash.
  def test_codex_hooks_entries_owned_survives_a_non_hash_hooks_value
    File.write(File.join(@codex_home, "hooks.json"), JSON.pretty_generate({ "hooks" => "not-a-hash" }))

    check = owned_check
    refute_nil check
    assert_equal "pass", check[:status]
    assert_empty Array(check[:details])
  end

  def test_unowned_plastic_prefixed_codex_entry_warns
    write_hooks_json
    hooks_json_path = File.join(@codex_home, "hooks.json")
    data = JSON.parse(File.read(hooks_json_path))
    data["hooks"]["SessionStart"].first["hooks"] << {
      "type" => "command", "command" => File.join(@codex_home, "plastic-writing-style"),
    }
    File.write(hooks_json_path, JSON.pretty_generate(data))

    check = owned_check
    assert_equal "warn", check[:status]
    details = Array(check[:details])
    assert_equal 1, details.size
    assert details.first.include?("reserved prefix"), "expected a reserved-prefix detail: #{details.inspect}"
  end

  def test_missing_codex_dispatcher_fails_codex_hooks_entries_owned
    write_hooks_json
    File.delete(@dispatcher_path)

    check = owned_check
    assert_equal "fail", check[:status]
    details = Array(check[:details])
    refute_empty details
    assert details.all? { |d| d.include?("missing launcher") }, "expected only missing-launcher details: #{details.inspect}"
  end

  # Codex's dispatcher path is always quoted ("<dispatcher>" <name>), so a
  # spaced plastic_home must resolve exactly as well as an unspaced one
  # (review finding, round 2). Builds its own spaced home/dispatcher rather
  # than the shared setup's unspaced fixtures.
  def test_codex_hooks_entries_owned_passes_with_a_spaced_codex_home_when_dispatcher_present
    base = Dir.mktmpdir("plastic-doctor-codex-base")
    home = File.join(base, "my plastic home")
    FileUtils.mkdir_p(home)
    agent_dir = Dir.mktmpdir("plastic-doctor-codex-agents")
    codex_home = File.join(home, "codex home")
    FileUtils.mkdir_p(codex_home)
    dispatcher_path = File.join(home, "scripts", "codex-hook")
    FileUtils.mkdir_p(File.dirname(dispatcher_path))
    File.write(dispatcher_path, "#!/usr/bin/env ruby\n")
    File.chmod(0o755, dispatcher_path)
    hooks = HookRegistry.codex_hooks_json(dispatcher_path: dispatcher_path)
    File.write(File.join(codex_home, "hooks.json"), JSON.pretty_generate({ "hooks" => hooks }))

    d = Doctor.new(plastic_home: home,
                    agents: { "codex" => { name: "Codex CLI", dir: agent_dir, home_dir: codex_home } },
                    runner: ->(_args) { ["", false] })
    check = d.check_codex_registration("codex", agent_dir).find { |c| c[:name] == "codex_hooks_entries_owned" }

    assert_equal "pass", check[:status],
                 "a spaced codex home with the dispatcher present must not report it missing: #{Array(check[:details]).inspect}"
  ensure
    FileUtils.rm_rf(base) if base
    FileUtils.rm_rf(agent_dir) if agent_dir
  end

  def test_codex_hooks_entries_owned_fails_with_a_spaced_codex_home_when_dispatcher_absent
    base = Dir.mktmpdir("plastic-doctor-codex-base")
    home = File.join(base, "my plastic home")
    FileUtils.mkdir_p(home)
    agent_dir = Dir.mktmpdir("plastic-doctor-codex-agents")
    codex_home = File.join(home, "codex home")
    FileUtils.mkdir_p(codex_home)
    dispatcher_path = File.join(home, "scripts", "codex-hook")
    FileUtils.mkdir_p(File.dirname(dispatcher_path))
    File.write(dispatcher_path, "#!/usr/bin/env ruby\n")
    File.chmod(0o755, dispatcher_path)
    hooks = HookRegistry.codex_hooks_json(dispatcher_path: dispatcher_path)
    File.write(File.join(codex_home, "hooks.json"), JSON.pretty_generate({ "hooks" => hooks }))
    File.delete(dispatcher_path)

    d = Doctor.new(plastic_home: home,
                    agents: { "codex" => { name: "Codex CLI", dir: agent_dir, home_dir: codex_home } },
                    runner: ->(_args) { ["", false] })
    check = d.check_codex_registration("codex", agent_dir).find { |c| c[:name] == "codex_hooks_entries_owned" }

    assert_equal "fail", check[:status]
    details = Array(check[:details])
    refute_empty details
    assert details.all? { |d| d.include?("missing launcher") }, "expected only missing-launcher details: #{details.inspect}"
    assert details.any? { |d| d.include?("codex-hook") }, "the detail must name the codex-hook dispatcher: #{details.inspect}"
  ensure
    FileUtils.rm_rf(base) if base
    FileUtils.rm_rf(agent_dir) if agent_dir
  end

  # Item 2 BLOCKING (round 3): the same apostrophe requirement, Codex side.
  def test_codex_hooks_entries_owned_passes_with_an_apostrophe_in_the_codex_home_when_dispatcher_present
    base = Dir.mktmpdir("plastic-doctor-codex-apos-base")
    home = File.join(base, "o'brien plastic home")
    FileUtils.mkdir_p(home)
    agent_dir = Dir.mktmpdir("plastic-doctor-codex-agents")
    codex_home = File.join(home, "codex home")
    FileUtils.mkdir_p(codex_home)
    dispatcher_path = File.join(home, "scripts", "codex-hook")
    FileUtils.mkdir_p(File.dirname(dispatcher_path))
    File.write(dispatcher_path, "#!/usr/bin/env ruby\n")
    File.chmod(0o755, dispatcher_path)
    hooks = HookRegistry.codex_hooks_json(dispatcher_path: dispatcher_path)
    File.write(File.join(codex_home, "hooks.json"), JSON.pretty_generate({ "hooks" => hooks }))

    d = Doctor.new(plastic_home: home,
                    agents: { "codex" => { name: "Codex CLI", dir: agent_dir, home_dir: codex_home } },
                    runner: ->(_args) { ["", false] })
    check = d.check_codex_registration("codex", agent_dir).find { |c| c[:name] == "codex_hooks_entries_owned" }

    assert_equal "pass", check[:status],
                 "an apostrophe in the codex home must not report the dispatcher missing: #{Array(check[:details]).inspect}"
  ensure
    FileUtils.rm_rf(base) if base
    FileUtils.rm_rf(agent_dir) if agent_dir
  end
end

# ===========================================================================
# 3a. claude_hooks_implemented_check (intent 244, the Claude twin of intent
# 200's codex_hooks_implemented_check): scripts/hook-edit-gates now holds
# every edit-path gate as a `case gate` branch, which is the exact shape
# that let a registered gate ship with no dispatcher branch on Codex
# (links-gate, intent 198). Mirrors CodexInstallTest's
# codex_hooks_implemented fixtures in test/codex_install_test.rb: real
# files distributed into a tmp plastic_home via InstallerCore, then
# mutated on disk to force each failure mode.
# ===========================================================================

class DoctorClaudeHooksImplementedTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)

  def setup
    @home = Dir.mktmpdir("claude-hooks-implemented-home")
    @agent_dir = Dir.mktmpdir("claude-hooks-implemented-agent")
    @agents = [{ key: "claude", name: "Claude Code", dir: @agent_dir, flag: "--claude", skill_prefix: "/" }]
    @core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home,
                               agents: @agents, version: "1.0.0-test")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@agent_dir)
  end

  def dispatcher_path
    File.join(@home, "scripts", "hook-edit-gates")
  end

  def doctor_for(agent_dir)
    Doctor.new(plastic_home: @home, agents: { "claude" => { name: "Claude Code", dir: agent_dir } })
  end

  def test_claude_hooks_implemented_passes_on_the_real_healthy_dispatcher
    @core.distribute(:install) # copies the REAL scripts/hook-edit-gates into plastic_home
    @core.install_for_agent("claude", false)

    checks = doctor_for(@agent_dir).check_agent_registration("claude")
    implemented_check = checks.find { |c| c[:name] == "claude_hooks_implemented" }

    refute_nil implemented_check
    assert_equal "pass", implemented_check[:status]
  end

  def test_claude_hooks_implemented_fails_when_a_registered_gate_has_no_dispatcher_branch
    @core.distribute(:install)
    @core.install_for_agent("claude", false)
    content = File.read(dispatcher_path)
    branch_start = content.index('when "links-gate"')
    refute_nil branch_start, "fixture assumption: scripts/hook-edit-gates must still carry a links-gate branch"
    # Remove just the links-gate `when` arm up to (not including) the next
    # `when` or the case's closing `end`, whichever comes first.
    next_when = content.index(/\n\s*when /, branch_start + 1)
    end_line = content.index(/\n\s*end\b/, branch_start)
    cut_end = [next_when, end_line].compact.min
    refute_nil cut_end, "fixture assumption: the case statement must still be findable"
    File.write(dispatcher_path, content[0...branch_start] + content[cut_end..])

    checks = doctor_for(@agent_dir).check_agent_registration("claude")
    implemented_check = checks.find { |c| c[:name] == "claude_hooks_implemented" }

    refute_nil implemented_check
    assert_equal "fail", implemented_check[:status]
    assert(implemented_check[:details].any? { |d|
      d.include?("links-gate") && d.include?("GATE_TOOLS") && d.include?("never blocks anything")
    }, "expected a links-gate detail naming the direction and the fail-open runtime effect, got: #{implemented_check[:details].inspect}")
  end

  def test_claude_hooks_implemented_fails_when_the_dispatcher_has_a_branch_nobody_registers
    @core.distribute(:install)
    @core.install_for_agent("claude", false)
    content = File.read(dispatcher_path)
    marker = 'when "create-gate"'
    idx = content.index(marker)
    refute_nil idx, "fixture assumption: scripts/hook-edit-gates must still carry a create-gate branch"
    updated = content[0...idx] + "when \"phantom-gate\"\n      nil\n    " + content[idx..]
    File.write(dispatcher_path, updated)

    checks = doctor_for(@agent_dir).check_agent_registration("claude")
    implemented_check = checks.find { |c| c[:name] == "claude_hooks_implemented" }

    refute_nil implemented_check
    assert_equal "fail", implemented_check[:status]
    assert(implemented_check[:details].any? { |d| d.include?("phantom-gate") && d.include?("dead code") },
      "expected a phantom-gate detail naming it as dead/unreachable code, got: #{implemented_check[:details].inspect}")
  end

  def test_claude_hooks_implemented_fails_loudly_when_the_dispatcher_cannot_be_read
    @core.distribute(:install)
    @core.install_for_agent("claude", false)
    reshaped = <<~RUBY
      #!/usr/bin/env ruby
      # Reshaped fixture: no `case gate` statement, so the extractor must find
      # zero names and doctor must fail loudly rather than silently pass.
      GATES = {
        "code-gate" => ->(_x) { exit 0 },
        "lock-gate" => ->(_x) { exit 0 },
      }
      handler = GATES[ARGV[0]] || ->(_x) { exit(0) }
      handler.call(nil)
    RUBY
    File.write(dispatcher_path, reshaped)

    checks = doctor_for(@agent_dir).check_agent_registration("claude")
    implemented_check = checks.find { |c| c[:name] == "claude_hooks_implemented" }

    refute_nil implemented_check
    assert_equal "fail", implemented_check[:status]
    assert_includes implemented_check[:message], "Could not read"
  end

  def test_claude_dispatcher_gate_names_returns_nil_on_no_recognizable_names
    doctor = doctor_for(@agent_dir)
    assert_nil doctor.claude_dispatcher_gate_names("# nothing recognizable here\nexit 0\n")
  end
end

# ===========================================================================
# 4. Core Files checks
# ===========================================================================

class DoctorCoreFilesTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.rm_rf(DOCTOR_TEST_CLAUDE)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_CLAUDE)
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.rm_rf(DOCTOR_TEST_CLAUDE)
  end

  def build_core_files
    File.write(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"), "# Plastic\n")
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "1.0.0")
    write_core_scripts(File.join(DOCTOR_TEST_HOME, "scripts"))

    # Agent-side VERSION
    agent_version_dir = File.join(DOCTOR_TEST_CLAUDE, "plastic")
    FileUtils.mkdir_p(agent_version_dir)
    File.write(File.join(agent_version_dir, "VERSION"), "1.0.0")
  end

  def test_all_core_files_present_pass
    build_core_files

    checks = doctor.check_core_files("claude")
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_missing_plastic_md_fails
    build_core_files
    File.delete(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"))

    checks = doctor.check_core_files("claude")
    md_check = checks.find { |c| c[:name] == "plastic_md" }

    assert_equal "fail", md_check[:status]
  end

  def test_missing_scripts_fails
    build_core_files
    # Remove two scripts
    File.delete(File.join(DOCTOR_TEST_HOME, "scripts", "folgezettel-id"))
    File.delete(File.join(DOCTOR_TEST_HOME, "scripts", "read-config"))

    checks = doctor.check_core_files("claude")
    scripts_check = checks.find { |c| c[:name] == "scripts_present" }

    assert_equal "fail", scripts_check[:status]
    assert_equal 2, scripts_check[:details].size
  end

  def test_version_mismatch_warns
    build_core_files
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "2.0.0")
    # Agent side stays at 1.0.0

    checks = doctor.check_core_files("claude")
    version_check = checks.find { |c| c[:name] == "version_match" }

    assert_equal "warn", version_check[:status]
    assert version_check[:message].include?("2.0.0")
    assert version_check[:message].include?("1.0.0")
  end

  # AC8, falsifiable (intent 210): a version split is reinstall-fixable (npx install
  # --reinstall, or plastic-rollback), so this must report fixable: true with a
  # fix_hint, not the old fixable: false dead end.
  def test_version_mismatch_is_fixable_with_a_reinstall_hint
    build_core_files
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "2.0.0")

    checks = doctor.check_core_files("claude")
    version_check = checks.find { |c| c[:name] == "version_match" }

    assert_equal true, version_check[:fixable], "a version split must be reported as fixable, not a dead end"
    refute_nil version_check[:fix_hint]
    assert_match(/reinstall|rollback/i, version_check[:fix_hint])
  end

  def test_missing_agent_version_file_is_fixable
    build_core_files
    File.delete(File.join(DOCTOR_TEST_CLAUDE, "plastic", "VERSION"))

    checks = doctor.check_core_files("claude")
    version_check = checks.find { |c| c[:name] == "version_match" }

    assert_equal "warn", version_check[:status]
    assert_equal true, version_check[:fixable]
    refute_nil version_check[:fix_hint]
  end

  def test_missing_version_file_fails
    build_core_files
    File.delete(File.join(DOCTOR_TEST_HOME, "VERSION"))

    checks = doctor.check_core_files("claude")
    version_check = checks.find { |c| c[:name] == "version_file" }

    assert_equal "fail", version_check[:status]
  end

  def test_non_executable_scripts_fail
    build_core_files
    # Make one script non-executable
    File.chmod(0o644, File.join(DOCTOR_TEST_HOME, "scripts", "folgezettel-id"))

    checks = doctor.check_core_files("claude")
    exec_check = checks.find { |c| c[:name] == "scripts_executable" }

    assert_equal "fail", exec_check[:status]
    assert exec_check[:details].any? { |d| d.include?("folgezettel-id") }
  end
end

# ===========================================================================
# 5. Project Store checks
# ===========================================================================

class DoctorProjectStoresTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    @store_dir = File.join(DOCTOR_TEST_HOME, "store")
    FileUtils.mkdir_p(@store_dir)
    @projects_dir = File.join(DOCTOR_TEST_HOME, "projects")
    FileUtils.mkdir_p(@projects_dir)
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.rm_rf(File.join(Dir.tmpdir, "my-app-src-#{Process.pid}"))
  end

  def test_valid_project_setup_passes
    project_path = File.join(Dir.tmpdir, "my-app-src-#{Process.pid}")
    # Register a project
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => {
        "my-app" => { "path" => project_path },
      },
    }))

    # Create the project directory with INDEX.md and project.yml
    project_dir = File.join(@projects_dir, "my-app")
    project_path = File.join(Dir.tmpdir, "my-app-src-#{Process.pid}")
    FileUtils.mkdir_p(project_dir)
    FileUtils.mkdir_p(File.join(project_dir, "store"))
    FileUtils.mkdir_p(project_path)
    File.write(File.join(project_dir, "INDEX.md"), "# My App Index\n")
    File.write(File.join(project_dir, "project.yml"), YAML.dump({
      "governing_docs" => ["AGENTS.md"],
    }))
    File.write(File.join(project_path, "AGENTS.md"), "# Agents\n")

    checks = doctor.check_project_stores
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_missing_project_directory_warns
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => {
        "missing-app" => { "path" => "/tmp/missing-app" },
      },
    }))

    checks = doctor.check_project_stores
    dir_check = checks.find { |c| c[:name] == "project_dir_exists" }

    assert_equal "warn", dir_check[:status]
    assert dir_check[:message].include?("missing-app")
  end

  def test_missing_project_index_warns
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => {
        "no-index" => { "path" => "/tmp/no-index" },
      },
    }))

    # Create directory but no INDEX.md
    FileUtils.mkdir_p(File.join(@projects_dir, "no-index"))

    checks = doctor.check_project_stores
    index_check = checks.find { |c| c[:name] == "project_index" }

    assert_equal "warn", index_check[:status]
    assert index_check[:message].include?("no-index")
  end

  # intent 61: additive project_store_dir check
  def test_missing_store_dir_warns_and_is_fixable
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => {
        "no-store" => { "path" => "/tmp/no-store" },
      },
    }))

    # Create the project dir + INDEX.md + project.yml but NOT store/
    project_dir = File.join(@projects_dir, "no-store")
    FileUtils.mkdir_p(project_dir)
    File.write(File.join(project_dir, "INDEX.md"), "# Index\n")
    File.write(File.join(project_dir, "project.yml"), YAML.dump({ "governing_docs" => ["AGENTS.md"] }))

    checks = doctor.check_project_stores
    store_check = checks.find { |c| c[:name] == "project_store_dir" }

    refute_nil store_check, "project_store_dir check should be present"
    assert_equal "warn", store_check[:status]
    assert_equal true, store_check[:fixable]
    assert_includes store_check[:fix_hint], "provision-project-store"
    assert store_check[:message].include?("no-store")
  end

  def test_present_store_dir_passes
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => {
        "has-store" => { "path" => "/tmp/has-store" },
      },
    }))

    project_dir = File.join(@projects_dir, "has-store")
    FileUtils.mkdir_p(File.join(project_dir, "store"))

    checks = doctor.check_project_stores
    store_check = checks.find { |c| c[:name] == "project_store_dir" }

    refute_nil store_check
    assert_equal "pass", store_check[:status]
  end

  def test_missing_projects_yml_warns
    # No projects.yml at all
    checks = doctor.check_project_stores

    assert_equal 1, checks.size
    assert_equal "projects_yml", checks[0][:name]
    assert_equal "warn", checks[0][:status]
  end

  def test_empty_projects_hash_passes
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => {},
    }))

    checks = doctor.check_project_stores

    assert_equal 1, checks.size
    assert_equal "projects_yml", checks[0][:name]
    assert_equal "pass", checks[0][:status]
  end
end

# ===========================================================================
# 6. Deprecations checks
# ===========================================================================

class DoctorDeprecationsTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
  end

  def test_no_deprecations_file_passes
    checks = doctor.check_deprecations

    assert_equal 1, checks.size
    assert_equal "pass", checks[0][:status]
  end

  def test_empty_deprecations_list_passes
    File.write(File.join(DOCTOR_TEST_HOME, "deprecations.yml"), YAML.dump({
      "deprecations" => [],
    }))

    checks = doctor.check_deprecations
    active_check = checks.find { |c| c[:name] == "active_deprecations" }

    refute_nil active_check, "active_deprecations check should be present for an empty list"
    assert_equal "pass", active_check[:status]
  end

  def test_no_active_deprecations_passes
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "2.0.0")
    File.write(File.join(DOCTOR_TEST_HOME, "deprecations.yml"), YAML.dump({
      "deprecations" => [
        { "summary" => "Old thing removed", "removal" => "1.0.0", "severity" => "breaking" },
      ],
    }))

    checks = doctor.check_deprecations
    active_check = checks.find { |c| c[:name] == "active_deprecations" }

    assert_equal "pass", active_check[:status]
  end

  def test_active_deprecation_warns
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "1.0.0")
    File.write(File.join(DOCTOR_TEST_HOME, "deprecations.yml"), YAML.dump({
      "deprecations" => [
        {
          "summary" => "Feature X will be removed",
          "removal" => "2.0.0",
          "severity" => "warning",
          "migration_steps" => ["Step 1", "Step 2"],
        },
      ],
    }))

    checks = doctor.check_deprecations
    active_check = checks.find { |c| c[:name] == "active_deprecations" }

    assert_equal "warn", active_check[:status]
    assert active_check[:details].any? { |d| d.include?("Feature X") }
  end

  def test_missing_version_file_warns
    File.write(File.join(DOCTOR_TEST_HOME, "deprecations.yml"), YAML.dump({
      "deprecations" => [
        { "summary" => "Something", "removal" => "2.0.0", "severity" => "warning" },
      ],
    }))

    checks = doctor.check_deprecations
    active_check = checks.find { |c| c[:name] == "active_deprecations" }

    assert_equal "warn", active_check[:status]
    assert active_check[:message].include?("VERSION file missing")
  end
end

# ===========================================================================
# 7. Integration — doctor.run_checks
# ===========================================================================

class DoctorIntegrationTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.rm_rf(DOCTOR_TEST_CLAUDE)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_CLAUDE)
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.rm_rf(DOCTOR_TEST_CLAUDE)
  end

  def build_healthy_installation
    # Global store
    store_dir = File.join(DOCTOR_TEST_HOME, "store")
    FileUtils.mkdir_p(store_dir)
    write_intent(store_dir, "1a--healthy")
    write_index(File.join(DOCTOR_TEST_HOME, "INDEX.md"), store_refs: ["store/1a--healthy"])

    # Core files
    File.write(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"), "# Plastic\n")
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "1.0.0")
    write_core_scripts(File.join(DOCTOR_TEST_HOME, "scripts"))

    # Agent-side manifest.json, present before write_skills/write_agents so
    # track_in_agent_manifest (a no-op without one) actually records what
    # gets installed — a real install always ships this file, and
    # stray_skills (intent 276) now warns when skills exist without one.
    agent_manifest = File.join(DOCTOR_TEST_CLAUDE, "plastic", "manifest.json")
    FileUtils.mkdir_p(File.dirname(agent_manifest))
    File.write(agent_manifest, JSON.pretty_generate({ "files" => {} }))

    # Agent registration
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_claude_dispatcher(DOCTOR_TEST_HOME)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    write_agents(DOCTOR_TEST_CLAUDE)

    # Agent-side VERSION
    agent_plastic = File.join(DOCTOR_TEST_CLAUDE, "plastic")
    FileUtils.mkdir_p(agent_plastic)
    File.write(File.join(agent_plastic, "VERSION"), "1.0.0")

    # projects.yml (empty — no projects)
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({ "projects" => {} }))
  end

  def test_run_checks_returns_valid_json_structure
    build_healthy_installation

    result = doctor.run_checks("claude")

    assert_equal "1.0.0", result[:version]
    assert result[:timestamp]
    assert_equal "claude", result[:agent]
    assert result[:checks].is_a?(Array)
    assert result[:summary].is_a?(Hash)
    assert %w[pass warn fail].include?(result[:status])
  end

  def test_summary_counts_match_actual_statuses
    build_healthy_installation

    result = doctor.run_checks("claude")
    summary = result[:summary]

    actual_pass = result[:checks].count { |c| c[:status] == "pass" }
    actual_warn = result[:checks].count { |c| c[:status] == "warn" }
    actual_fail = result[:checks].count { |c| c[:status] == "fail" }

    assert_equal actual_pass, summary[:pass], "Summary pass count should match"
    assert_equal actual_warn, summary[:warn], "Summary warn count should match"
    assert_equal actual_fail, summary[:fail], "Summary fail count should match"
    assert_equal result[:checks].size, summary[:total], "Summary total should match"
  end

  def test_healthy_installation_status_is_pass
    build_healthy_installation

    result = doctor.run_checks("claude")

    assert_equal "pass", result[:status], "Healthy installation should have pass status, failures: #{
      result[:checks].reject { |c| c[:status] == "pass" }.map { |c| [c[:name], c[:status], c[:message]] }
    }"
  end

  def test_status_fail_when_failures_present
    # Missing everything — will produce failures
    result = doctor.run_checks("claude")

    assert_equal "fail", result[:status]
    assert result[:summary][:fail] > 0
  end

  def test_status_warn_when_only_warnings
    build_healthy_installation
    # Add an orphaned intent to trigger a warn (but no fails)
    store_dir = File.join(DOCTOR_TEST_HOME, "store")
    write_intent(store_dir, "2b--orphan")

    result = doctor.run_checks("claude")

    # Should have at least one warning from the orphan
    assert result[:summary][:warn] > 0, "Should have warnings"

    # If there are no failures, overall should be "warn"
    if result[:summary][:fail] == 0
      assert_equal "warn", result[:status]
    end
  end

  def test_each_check_has_required_fields
    build_healthy_installation

    result = doctor.run_checks("claude")
    required_keys = %i[category name status message details fixable]

    result[:checks].each do |c|
      required_keys.each do |key|
        assert c.key?(key), "Check '#{c[:name]}' missing required key :#{key}"
      end
      assert %w[pass warn fail].include?(c[:status]), "Check '#{c[:name]}' has invalid status: #{c[:status]}"
    end
  end
end

# ===========================================================================
# 8. Version comparison helper
# ===========================================================================

# ===========================================================================
# 9. Task C — `--store [global|<project>]` scoping
# ===========================================================================

class DoctorStoreScopingTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)

    # Global store with one intent + INDEX referencing it.
    @global_store = File.join(DOCTOR_TEST_HOME, "store")
    FileUtils.mkdir_p(@global_store)
    write_intent(@global_store, "1a--global-intent")
    write_index(File.join(DOCTOR_TEST_HOME, "INDEX.md"), store_refs: ["store/1a--global-intent"])

    # One registered project with its own store + one intent.
    @project_slug = "plastic"
    project_dir = File.join(DOCTOR_TEST_HOME, "projects", @project_slug)
    @project_store = File.join(project_dir, "store")
    FileUtils.mkdir_p(@project_store)
    write_intent(@project_store, "2b--project-intent")
    File.write(File.join(project_dir, "INDEX.md"), "# Project Index\n")

    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => { @project_slug => { "path" => File.join(Dir.tmpdir, "plastic-src-#{Process.pid}") } },
    }))
  end

  def teardown
    FileUtils.rm_rf(DOCTOR_TEST_HOME)
  end

  # --- parse_args ---

  def test_parse_store_no_value_is_all
    flags = doctor.parse_args(["--store"])
    assert_equal :all, flags[:store]
  end

  def test_parse_store_global
    flags = doctor.parse_args(["--store", "global"])
    assert_equal :global, flags[:store]
  end

  def test_parse_store_slug
    flags = doctor.parse_args(["--store", "plastic"])
    assert_equal "plastic", flags[:store]
  end

  def test_parse_store_absent
    flags = doctor.parse_args([])
    assert_nil flags[:store]
  end

  def test_parse_store_followed_by_flag_is_all
    flags = doctor.parse_args(["--store", "--agent", "codex"])
    assert_equal :all, flags[:store]
    assert_equal "codex", flags[:agent]
  end

  # --- check_conventions scoping ---

  def test_conventions_scoped_to_global_excludes_project
    checks = doctor.check_conventions(scopes: ["global"])
    dirname = checks.find { |c| c[:name] == "intent_dirname" }
    assert_includes dirname[:message], "1", "should count the single global intent"
    # The project intent name should not appear anywhere in details.
    assert checks.none? { |c| (c[:details] || []).any? { |d| d.include?("2b--project-intent") } }
  end

  def test_conventions_nil_scope_covers_all
    checks = doctor.check_conventions
    dirname = checks.find { |c| c[:name] == "intent_dirname" }
    assert_includes dirname[:message], "2", "nil scope should count both intents"
  end

  # --- run_store_checks ---

  def test_store_global_excludes_project_intent
    result = doctor.run_store_checks(:global)
    all_text = result[:checks].to_json
    refute_includes all_text, "2b--project-intent", "global scope must not touch project intent"
  end

  def test_store_slug_covers_only_that_project
    result = doctor.run_store_checks(@project_slug)
    categories = result[:checks].map { |c| c[:category] }.uniq
    assert_includes categories, "project_stores"
    assert_includes categories, "conventions"
    # global store category should not be present
    refute_includes categories, "global_store"
  end

  # intent 61: the --store <slug> path includes the additive project_store_dir
  # check, and it passes because setup already created @project_store.
  def test_store_slug_includes_passing_project_store_dir
    result = doctor.run_store_checks(@project_slug)
    store_check = result[:checks].find { |c| c[:name] == "project_store_dir" }
    refute_nil store_check, "project_store_dir should be in the --store <slug> result"
    assert_equal "pass", store_check[:status]
  end

  def test_store_all_covers_both
    result = doctor.run_store_checks(:all)
    categories = result[:checks].map { |c| c[:category] }.uniq
    assert_includes categories, "global_store"
    assert_includes categories, "project_stores"
    assert_includes categories, "conventions"
  end

  def test_store_unknown_slug_is_fail
    result = doctor.run_store_checks("does-not-exist")
    assert_equal "fail", result[:status]
    assert result[:checks].any? { |c| c[:message].include?("does-not-exist") }
  end

  def test_store_global_has_three_state_envelope
    result = doctor.run_store_checks(:global)
    %i[version timestamp status agent checks summary].each do |key|
      assert result.key?(key), "store result missing envelope key #{key}"
    end
  end

  # Fake `qmd collection list` output reporting both collections these tests touch
  # (plastic-global and the @project_slug collection) as already registered, so
  # check_qmd's scoped "collections" check reaches its pass branch deterministically
  # (intent 221a) regardless of whether the executing host actually has QMD
  # installed or any collections registered.
  def fake_qmd_collection_list_runner
    ->(_args) {
      ["plastic-global (qmd://plastic-global/)\nplastic-#{@project_slug} (qmd://plastic-#{@project_slug}/)\n", true]
    }
  end

  def test_store_global_includes_scoped_qmd_but_no_tool_checks
    result = doctor.run_store_checks(:global, qmd_detector: -> { true }, qmd_runner: fake_qmd_collection_list_runner)
    names = result[:checks].map { |c| c[:name] }

    assert_includes names, "present" # check_qmd's own "present" check name
    refute_includes names, "serena_ready"
    refute_includes names, "enola_ready"
  end

  def test_store_slug_includes_qmd_and_both_tool_checks
    result = doctor.run_store_checks(
      @project_slug,
      qmd_detector: -> { true }, qmd_runner: fake_qmd_collection_list_runner,
      serena_path_probe: -> { false }, serena_marker_finder: ->(_cwd) { false },
      enola_path_probe: -> { false }, enola_marker_finder: ->(_cwd) { false }
    )
    names = result[:checks].map { |c| c[:name] }

    assert_includes names, "collections" # check_qmd's scoped collection check
    assert_includes names, "serena_ready"
    assert_includes names, "enola_ready"
  end

  # D5 no-leak guarantee: a project registered with a real violation (its own store
  # directory missing) must be invisible to run_checks and visible to run_store_checks(slug).
  def test_run_checks_never_leaks_a_project_finding_run_store_checks_does
    FileUtils.rm_rf(@project_store) # the registered project's store directory now does not exist

    full = doctor.run_checks("claude")
    scoped = doctor.run_store_checks(@project_slug)

    refute_includes full[:checks].map { |c| c[:category] }, "project_stores",
      "run_checks must carry zero project_stores findings after 221"
    # A raw substring search for @project_slug ("plastic") would false-positive on doctor's
    # own tmpdir/agent-file naming (e.g. "plastic-doctor-test-...", "installed plastic-*
    # agent files"), so assert against the actual leak signature: the quoted slug
    # check_project_store emits ("for 'plastic'"), not every occurrence of the substring.
    refute_includes full[:checks].to_json, "for '#{@project_slug}'",
      "run_checks must never mention a registered project's slug in a per-project finding"

    store_dir_check = scoped[:checks].find { |c| c[:name] == "project_store_dir" }
    refute_nil store_dir_check, "run_store_checks(slug) must surface the missing store directory"
    assert_equal "warn", store_dir_check[:status]
  end
end

class DoctorVersionCompareTest < Minitest::Test
  include DoctorTestHelpers
  def test_equal_versions
    assert_equal 0, doctor.compare_versions("1.0.0", "1.0.0")
  end

  def test_greater_version
    assert_equal 1, doctor.compare_versions("2.0.0", "1.0.0")
  end

  def test_lesser_version
    assert_equal(-1, doctor.compare_versions("1.0.0", "2.0.0"))
  end

  def test_minor_version_comparison
    assert_equal(-1, doctor.compare_versions("1.1.0", "1.2.0"))
  end

  def test_patch_version_comparison
    assert_equal 1, doctor.compare_versions("1.0.2", "1.0.1")
  end

  def test_prerelease_less_than_release
    assert_equal(-1, doctor.compare_versions("1.0.0-alpha", "1.0.0"))
  end

  def test_release_greater_than_prerelease
    assert_equal 1, doctor.compare_versions("1.0.0", "1.0.0-beta")
  end

  def test_prerelease_lexical_comparison
    assert_equal(-1, doctor.compare_versions("1.0.0-alpha", "1.0.0-beta"))
  end

  def test_different_length_versions
    assert_equal 0, doctor.compare_versions("1.0", "1.0.0")
  end
end

# Entry-point coverage (intent 169, Defect 2): scripts/doctor.rb's
# `$PROGRAM_NAME == __FILE__` entry reads `ENV["PLASTIC_HOME"]` and threads it
# into `Doctor.new(plastic_home:)`. The `Doctor` class itself stays DI
# (unchanged, covered by every other test above); this is the one focused
# subprocess test for the entry line, since it is a Defect-2 leak reader.
class DoctorEntryPlasticHomeTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/doctor.rb", __FILE__)

  def test_entry_honors_plastic_home_and_never_resolves_the_real_store
    Dir.mktmpdir("doctor-entry-home") do |sandbox|
      env = { "PLASTIC_HOME" => sandbox }
      stdout, _stderr, _status = Open3.capture3(env, "ruby", SCRIPT)

      assert_includes stdout, sandbox,
        "doctor entry must resolve the sandbox PLASTIC_HOME, not just fall to its default"
      real_plastic_home = File.join(Dir.home, ".plastic")
      refute_includes stdout, real_plastic_home,
        "doctor entry must not resolve the operator's real ~/.plastic store"
    end
  end
end
