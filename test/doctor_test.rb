require "minitest/autorun"
require "tmpdir"
require "json"
require "yaml"
require "fileutils"

DOCTOR_RB = File.expand_path("../../scripts/doctor.rb", __FILE__)

DOCTOR_TEST_HOME = File.join(Dir.tmpdir, "plastic-doctor-test-#{Process.pid}")
DOCTOR_TEST_CLAUDE = File.join(Dir.tmpdir, "plastic-doctor-claude-#{Process.pid}")
DOCTOR_TEST_CODEX = File.join(Dir.tmpdir, "plastic-doctor-codex-#{Process.pid}")
DOCTOR_TEST_HERMES = File.join(Dir.tmpdir, "plastic-doctor-hermes-#{Process.pid}")

code = File.read(DOCTOR_RB)
code = code.sub(/^main$/, "# main (suppressed by test)")
code = code.sub(/^PLASTIC_HOME = .*$/, "PLASTIC_HOME = \"#{DOCTOR_TEST_HOME}\"")
code = code.sub(
  /^AGENTS = \{.*?\}\.freeze$/m,
  <<~RUBY.chomp
    AGENTS = {
      "claude" => { name: "Claude Code", dir: "#{DOCTOR_TEST_CLAUDE}" },
      "codex"  => { name: "Codex CLI",   dir: "#{DOCTOR_TEST_CODEX}" },
      "hermes" => { name: "Hermes",      dir: "#{DOCTOR_TEST_HERMES}" },
    }.freeze
  RUBY
)
eval(code, TOPLEVEL_BINDING, DOCTOR_RB)

# ---------------------------------------------------------------------------
# Helpers shared across test classes
# ---------------------------------------------------------------------------

module DoctorTestHelpers
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
    content = "---\n#{yaml_str}\n---\n\n# #{name}\n"
    File.write(File.join(dir, "#{name}.md"), content)
    dir
  end

  # Build Claude hook scripts (thin wrappers)
  def write_claude_hooks(hooks_dir)
    FileUtils.mkdir_p(hooks_dir)
    CLAUDE_HOOK_SCRIPTS.each do |hook|
      path = File.join(hooks_dir, hook)
      File.write(path, "#!/bin/bash\nexit 0\n")
      File.chmod(0o755, path)
    end
  end

  # Build a valid Claude settings.json with all required hook events
  def write_claude_settings(settings_path)
    hooks = {}
    CLAUDE_HOOK_EVENTS.each do |event|
      hooks[event] = [
        {
          "matcher" => "",
          "hooks" => [
            { "type" => "command", "command" => "plastic-session-start" },
          ],
        },
      ]
    end
    File.write(settings_path, JSON.pretty_generate({ "hooks" => hooks }))
  end

  # Build flat, hyphen-namespaced personal skills (plastic-<name>/SKILL.md)
  def write_skills(agent_dir)
    skill_dir = File.join(agent_dir, "skills", "plastic-doctor")
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, "SKILL.md"), "# skill")
  end

  # Build all required core scripts
  def write_core_scripts(scripts_dir)
    FileUtils.mkdir_p(scripts_dir)
    REQUIRED_SCRIPTS.each do |script|
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

    checks = check_global_store
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
    assert_equal 4, checks.size, "Should have index_exists, index_sections, orphaned_intents, ghost_references"
  end

  def test_missing_index_fails
    checks = check_global_store

    assert_equal 1, checks.size, "Should return early with one check"
    assert_equal "index_exists", checks[0][:name]
    assert_equal "fail", checks[0][:status]
    assert checks[0][:fixable]
  end

  def test_index_missing_sections_fails
    File.write(File.join(DOCTOR_TEST_HOME, "INDEX.md"), "# Plastic\n\n## Active\n\n## Future\n")

    checks = check_global_store
    sections_check = checks.find { |c| c[:name] == "index_sections" }

    assert sections_check, "index_sections check should be present"
    assert_equal "fail", sections_check[:status]
    assert_equal 3, sections_check[:details].size, "Should report 3 missing sections (Clusters, Abandoned, Completed)"
  end

  def test_orphaned_intent_warns
    write_intent(@store_dir, "1a--orphan")
    write_index(File.join(DOCTOR_TEST_HOME, "INDEX.md"))

    checks = check_global_store
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

    checks = check_global_store
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

    checks = check_conventions
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All convention checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_bad_dirname_warns
    # Create a directory without the -- separator
    bad_dir = File.join(@store_dir, "no-separator")
    FileUtils.mkdir_p(bad_dir)
    File.write(File.join(bad_dir, "no-separator.md"), "# test\n")

    checks = check_conventions
    dirname_check = checks.find { |c| c[:name] == "intent_dirname" }

    assert_equal "warn", dirname_check[:status]
    assert dirname_check[:details].any? { |d| d.include?("no-separator") }
  end

  def test_missing_primary_md_warns
    dir = File.join(@store_dir, "1a--missing-file")
    FileUtils.mkdir_p(dir)
    # Write a file with a non-matching name
    File.write(File.join(dir, "wrong-name.md"), "# wrong\n")

    checks = check_conventions
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

    checks = check_conventions
    fm_check = checks.find { |c| c[:name] == "frontmatter_fields" }

    assert_equal "warn", fm_check[:status]
    assert fm_check[:details].any? { |d| d.include?("sources") }
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
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = check_agent_registration("claude")
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_missing_hook_scripts_fails
    # Create hooks dir but only write some hooks
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    FileUtils.mkdir_p(hooks_dir)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = check_agent_registration("claude")
    hooks_check = checks.find { |c| c[:name] == "hooks_exist" }

    assert_equal "fail", hooks_check[:status]
    assert_equal CLAUDE_HOOK_SCRIPTS.size, hooks_check[:details].size
  end

  def test_non_executable_hooks_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    FileUtils.mkdir_p(hooks_dir)
    # Write hooks but don't make them executable
    CLAUDE_HOOK_SCRIPTS.each do |hook|
      path = File.join(hooks_dir, hook)
      File.write(path, "#!/bin/bash\nexit 0\n")
      File.chmod(0o644, path)
    end
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    checks = check_agent_registration("claude")
    exec_check = checks.find { |c| c[:name] == "hooks_executable" }

    assert_equal "fail", exec_check[:status]
    assert_equal CLAUDE_HOOK_SCRIPTS.size, exec_check[:details].size
  end

  def test_missing_settings_entries_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_skills(DOCTOR_TEST_CLAUDE)
    # Write settings without any hooks
    File.write(File.join(DOCTOR_TEST_CLAUDE, "settings.json"), JSON.pretty_generate({ "hooks" => {} }))

    checks = check_agent_registration("claude")
    registered_check = checks.find { |c| c[:name] == "hooks_registered" }

    assert_equal "fail", registered_check[:status]
    assert_equal CLAUDE_HOOK_EVENTS.size, registered_check[:details].size
  end

  def test_missing_settings_json_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_skills(DOCTOR_TEST_CLAUDE)
    # No settings.json at all

    checks = check_agent_registration("claude")
    registered_check = checks.find { |c| c[:name] == "hooks_registered" }

    assert_equal "fail", registered_check[:status]
  end

  def test_missing_skills_directory_fails
    hooks_dir = File.join(DOCTOR_TEST_CLAUDE, "hooks")
    write_claude_hooks(hooks_dir)
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    # No skills directory

    checks = check_agent_registration("claude")
    skills_check = checks.find { |c| c[:name] == "skills_exist" }

    assert_equal "fail", skills_check[:status]
  end

  def test_missing_agent_dir_fails
    FileUtils.rm_rf(DOCTOR_TEST_CLAUDE)

    checks = check_agent_registration("claude")

    assert_equal 1, checks.size
    assert_equal "agent_dir_exists", checks[0][:name]
    assert_equal "fail", checks[0][:status]
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

    checks = check_core_files("claude")
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_missing_plastic_md_fails
    build_core_files
    File.delete(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"))

    checks = check_core_files("claude")
    md_check = checks.find { |c| c[:name] == "plastic_md" }

    assert_equal "fail", md_check[:status]
  end

  def test_missing_scripts_fails
    build_core_files
    # Remove two scripts
    File.delete(File.join(DOCTOR_TEST_HOME, "scripts", "folgezettel-id"))
    File.delete(File.join(DOCTOR_TEST_HOME, "scripts", "read-config"))

    checks = check_core_files("claude")
    scripts_check = checks.find { |c| c[:name] == "scripts_present" }

    assert_equal "fail", scripts_check[:status]
    assert_equal 2, scripts_check[:details].size
  end

  def test_version_mismatch_warns
    build_core_files
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "2.0.0")
    # Agent side stays at 1.0.0

    checks = check_core_files("claude")
    version_check = checks.find { |c| c[:name] == "version_match" }

    assert_equal "warn", version_check[:status]
    assert version_check[:message].include?("2.0.0")
    assert version_check[:message].include?("1.0.0")
  end

  def test_missing_version_file_fails
    build_core_files
    File.delete(File.join(DOCTOR_TEST_HOME, "VERSION"))

    checks = check_core_files("claude")
    version_check = checks.find { |c| c[:name] == "version_file" }

    assert_equal "fail", version_check[:status]
  end

  def test_non_executable_scripts_fail
    build_core_files
    # Make one script non-executable
    File.chmod(0o644, File.join(DOCTOR_TEST_HOME, "scripts", "folgezettel-id"))

    checks = check_core_files("claude")
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
    FileUtils.mkdir_p(project_path)
    File.write(File.join(project_dir, "INDEX.md"), "# My App Index\n")
    File.write(File.join(project_dir, "project.yml"), YAML.dump({
      "governing_docs" => ["AGENTS.md"],
    }))
    File.write(File.join(project_path, "AGENTS.md"), "# Agents\n")

    checks = check_project_stores
    statuses = checks.map { |c| c[:status] }

    assert statuses.all? { |s| s == "pass" }, "All checks should pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_missing_project_directory_warns
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => {
        "missing-app" => { "path" => "/tmp/missing-app" },
      },
    }))

    checks = check_project_stores
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

    checks = check_project_stores
    index_check = checks.find { |c| c[:name] == "project_index" }

    assert_equal "warn", index_check[:status]
    assert index_check[:message].include?("no-index")
  end

  def test_missing_projects_yml_warns
    # No projects.yml at all
    checks = check_project_stores

    assert_equal 1, checks.size
    assert_equal "projects_yml", checks[0][:name]
    assert_equal "warn", checks[0][:status]
  end

  def test_empty_projects_hash_passes
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({
      "projects" => {},
    }))

    checks = check_project_stores

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
    checks = check_deprecations

    assert_equal 1, checks.size
    assert_equal "pass", checks[0][:status]
  end

  def test_no_active_deprecations_passes
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "2.0.0")
    File.write(File.join(DOCTOR_TEST_HOME, "deprecations.yml"), YAML.dump({
      "deprecations" => [
        { "summary" => "Old thing removed", "removal" => "1.0.0", "severity" => "breaking" },
      ],
    }))

    checks = check_deprecations
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

    checks = check_deprecations
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

    checks = check_deprecations
    active_check = checks.find { |c| c[:name] == "active_deprecations" }

    assert_equal "warn", active_check[:status]
    assert active_check[:message].include?("VERSION file missing")
  end
end

# ===========================================================================
# 7. Integration — run_checks
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

    # Agent registration
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)

    # Agent-side VERSION
    agent_plastic = File.join(DOCTOR_TEST_CLAUDE, "plastic")
    FileUtils.mkdir_p(agent_plastic)
    File.write(File.join(agent_plastic, "VERSION"), "1.0.0")

    # projects.yml (empty — no projects)
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump({ "projects" => {} }))
  end

  def test_run_checks_returns_valid_json_structure
    build_healthy_installation

    result = run_checks("claude")

    assert_equal "1.0.0", result[:version]
    assert result[:timestamp]
    assert_equal "claude", result[:agent]
    assert result[:checks].is_a?(Array)
    assert result[:summary].is_a?(Hash)
    assert %w[pass warn fail].include?(result[:status])
  end

  def test_summary_counts_match_actual_statuses
    build_healthy_installation

    result = run_checks("claude")
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

    result = run_checks("claude")

    assert_equal "pass", result[:status], "Healthy installation should have pass status, failures: #{
      result[:checks].reject { |c| c[:status] == "pass" }.map { |c| [c[:name], c[:status], c[:message]] }
    }"
  end

  def test_status_fail_when_failures_present
    # Missing everything — will produce failures
    result = run_checks("claude")

    assert_equal "fail", result[:status]
    assert result[:summary][:fail] > 0
  end

  def test_status_warn_when_only_warnings
    build_healthy_installation
    # Add an orphaned intent to trigger a warn (but no fails)
    store_dir = File.join(DOCTOR_TEST_HOME, "store")
    write_intent(store_dir, "2b--orphan")

    result = run_checks("claude")

    # Should have at least one warning from the orphan
    assert result[:summary][:warn] > 0, "Should have warnings"

    # If there are no failures, overall should be "warn"
    if result[:summary][:fail] == 0
      assert_equal "warn", result[:status]
    end
  end

  def test_each_check_has_required_fields
    build_healthy_installation

    result = run_checks("claude")
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

class DoctorVersionCompareTest < Minitest::Test
  def test_equal_versions
    assert_equal 0, compare_versions("1.0.0", "1.0.0")
  end

  def test_greater_version
    assert_equal 1, compare_versions("2.0.0", "1.0.0")
  end

  def test_lesser_version
    assert_equal(-1, compare_versions("1.0.0", "2.0.0"))
  end

  def test_minor_version_comparison
    assert_equal(-1, compare_versions("1.1.0", "1.2.0"))
  end

  def test_patch_version_comparison
    assert_equal 1, compare_versions("1.0.2", "1.0.1")
  end

  def test_prerelease_less_than_release
    assert_equal(-1, compare_versions("1.0.0-alpha", "1.0.0"))
  end

  def test_release_greater_than_prerelease
    assert_equal 1, compare_versions("1.0.0", "1.0.0-beta")
  end

  def test_prerelease_lexical_comparison
    assert_equal(-1, compare_versions("1.0.0-alpha", "1.0.0-beta"))
  end

  def test_different_length_versions
    assert_equal 0, compare_versions("1.0", "1.0.0")
  end
end
