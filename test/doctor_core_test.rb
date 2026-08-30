require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"

require_relative "../scripts/doctor"
require_relative "doctor_test" # reuse DoctorTestHelpers + DOCTOR_TEST_* constants

# Coverage for the `--core` fast path: it runs only the runtime-liveness checks
# (agent registration + core files) and skips the slow inventory walks
# (global store, conventions, project stores, deprecations).
class DoctorCoreFlagTest < Minitest::Test
  include DoctorTestHelpers

  INVENTORY_NAMES = %w[
    index_exists index_sections orphaned_intents ghost_references
    intent_dirname intent_filename frontmatter_fields
    project_dir_exists project_index project_yml_exists governing_docs_exist
    cross_references active_deprecations deprecations_file
    agent_model_drift
  ].freeze

  def setup
    FileUtils.rm_rf([DOCTOR_TEST_HOME, DOCTOR_TEST_CLAUDE])
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_CLAUDE)
  end

  def teardown
    FileUtils.rm_rf([DOCTOR_TEST_HOME, DOCTOR_TEST_CLAUDE])
  end

  # --- flag parsing ---

  def test_parse_core_flag
    flags = doctor.parse_args(["--core"])
    assert_equal true, flags[:core]
    assert_equal "claude", flags[:agent]
  end

  def test_parse_core_with_agent
    flags = doctor.parse_args(["--core", "--agent", "codex"])
    assert_equal true, flags[:core]
    assert_equal "codex", flags[:agent]
  end

  def test_core_defaults_false
    flags = doctor.parse_args([])
    assert_equal false, flags[:core]
  end

  # --- check selection ---

  def test_core_run_excludes_inventory_checks
    result = doctor.run_core_checks("claude")
    names = result[:checks].map { |c| c[:name] }

    INVENTORY_NAMES.each do |inv|
      refute_includes names, inv, "--core must not run inventory check '#{inv}'"
    end
  end

  def test_core_run_is_exactly_the_five_liveness_groups
    d = doctor
    expected = (d.check_agent_registration("claude") +
                d.check_core_files("claude", include_drift: false) +
                d.check_manifest_sync("claude") +
                d.check_registered_project_paths +
                d.check_global_store_available)
               .map { |c| c[:name] }
    actual = d.run_core_checks("claude")[:checks].map { |c| c[:name] }

    assert_equal expected, actual,
      "--core must be exactly agent_registration + core_files(no drift) + manifest_sync + " \
      "registered_project_paths + global_store_available, in order"
  end

  def test_core_run_only_has_liveness_categories
    result = doctor.run_core_checks("claude")
    categories = result[:checks].map { |c| c[:category] }.uniq

    assert_equal %w[agent_registration core_files global_store manifest_sync project_stores],
      categories.sort,
      "--core categories should be agent_registration, core_files, global_store, " \
      "manifest_sync, and project_stores"
  end

  def test_core_run_has_standard_envelope
    result = doctor.run_core_checks("claude")
    %i[version timestamp status agent checks summary].each do |key|
      assert result.key?(key), "core result missing envelope key #{key}"
    end
    assert_equal "claude", result[:agent]
    assert_equal result[:checks].size, result[:summary][:total]
  end

  def test_core_summary_counts_only_liveness
    result = doctor.run_core_checks("claude")
    counted = result[:summary].values_at(:pass, :warn, :fail).sum
    assert_equal result[:checks].size, counted
  end

  # --- regression: full run still walks inventory ---

  def test_full_run_still_includes_inventory_categories
    result = doctor.run_checks("claude")
    categories = result[:checks].map { |c| c[:category] }.uniq

    %w[global_store conventions deprecations session_ledger done_signals].each do |cat|
      assert_includes categories, cat, "full doctor must still run '#{cat}' category"
    end
  end

  # 221 D5: run_checks must never carry a project_stores finding; that is
  # run_store_checks(slug)'s job now.
  def test_full_run_never_includes_project_stores_category
    result = doctor.run_checks("claude")
    categories = result[:checks].map { |c| c[:category] }.uniq

    refute_includes categories, "project_stores",
      "run_checks must never carry a project_stores finding after 221's re-homing"
  end

  def test_core_liveness_checks_are_subset_of_full_run
    # manifest_sync, registered_project_paths, and global_store_available are core-only;
    # the rest of --core must also appear in the full run.
    core_only_names = (doctor.check_manifest_sync("claude") +
                        doctor.check_registered_project_paths +
                        doctor.check_global_store_available).map { |c| c[:name] }
    core_names = doctor.run_core_checks("claude")[:checks].map { |c| c[:name] }
    full_names = doctor.run_checks("claude")[:checks].map { |c| c[:name] }

    extra = (core_names - core_only_names) - full_names
    assert_empty extra, "non-carved-out core checks not present in full run: #{extra.inspect}"
  end

  # --- check_registered_project_paths ---

  def test_registered_project_paths_passes_when_none_registered
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump("projects" => {}))

    checks = doctor.check_registered_project_paths
    check = checks.find { |c| c[:name] == "registered_project_paths" }

    refute_nil check
    assert_equal "pass", check[:status]
  end

  def test_registered_project_paths_fails_on_missing_projects_yml
    # No projects.yml written at all.
    checks = doctor.check_registered_project_paths
    check = checks.find { |c| c[:name] == "registered_project_paths" }

    refute_nil check
    assert_equal "fail", check[:status]
  end

  def test_project_path_resolves_passes_for_a_real_directory
    real_dir = Dir.mktmpdir("plastic-doctor-project-path")
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"),
      YAML.dump("projects" => { "demo" => { "path" => real_dir } }))

    checks = doctor.check_registered_project_paths
    check = checks.find { |c| c[:name] == "project_path_resolves" }

    refute_nil check
    assert_equal "pass", check[:status]
  ensure
    FileUtils.rm_rf(real_dir)
  end

  def test_project_path_resolves_fails_for_a_nonexistent_directory
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"),
      YAML.dump("projects" => { "demo" => { "path" => "/nonexistent/plastic-demo-dir" } }))

    checks = doctor.check_registered_project_paths
    check = checks.find { |c| c[:name] == "project_path_resolves" }

    refute_nil check
    assert_equal "fail", check[:status]
    assert check[:message].include?("demo"), "expected failure to name the slug"
  end

  # --- check_global_store_available ---

  def test_global_store_available_passes_when_intact
    File.write(File.join(DOCTOR_TEST_HOME, "INDEX.md"), "# Index\n")

    checks = doctor.check_global_store_available
    assert checks.all? { |c| c[:status] == "pass" },
      "expected all pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_global_index_reachable_fails_when_index_missing
    # DOCTOR_TEST_HOME exists (directory) but INDEX.md is not written.
    checks = doctor.check_global_store_available
    check = checks.find { |c| c[:name] == "global_index_reachable" }

    refute_nil check
    assert_equal "fail", check[:status]
  end

  def test_global_store_available_has_no_content_scanning_checks
    File.write(File.join(DOCTOR_TEST_HOME, "INDEX.md"), "# Index\n")
    names = doctor.check_global_store_available.map { |c| c[:name] }

    refute_includes names, "orphaned_intents"
    refute_includes names, "ghost_references"
  end
end

# ===========================================================================
# Task B — binary manifest-sync core check
# ===========================================================================

require "digest"

class DoctorManifestSyncTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf([DOCTOR_TEST_HOME, DOCTOR_TEST_CLAUDE])
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_CLAUDE)
  end

  def teardown
    FileUtils.rm_rf([DOCTOR_TEST_HOME, DOCTOR_TEST_CLAUDE])
  end

  # Write a real file and return [abs_path, sha256].
  def write_tracked(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    [path, Digest::SHA256.file(path).hexdigest]
  end

  def write_manifest(path, file_hashes)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate({
      "version" => "1.0.0",
      "created" => "2026-06-01",
      "files" => file_hashes,
    }))
  end

  # Build a hermetic install whose global + agent manifests both match on disk.
  # Returns the two tracked agent/global file paths so tests can tamper them.
  def build_intact_install
    global_file, global_hash = write_tracked(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"), "# Plastic\n")
    write_manifest(File.join(DOCTOR_TEST_HOME, "manifest.json"), { global_file => global_hash })

    agent_file, agent_hash = write_tracked(
      File.join(DOCTOR_TEST_CLAUDE, "plastic", "VERSION"), "1.0.0"
    )
    write_manifest(
      File.join(DOCTOR_TEST_CLAUDE, "plastic", "manifest.json"),
      { agent_file => agent_hash }
    )

    { global_file: global_file, agent_file: agent_file }
  end

  def test_intact_install_manifest_sync_passes
    build_intact_install

    checks = doctor.check_manifest_sync("claude")
    assert checks.all? { |c| c[:status] == "pass" },
      "Expected all pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
    assert_equal ["manifest_sync"], checks.map { |c| c[:category] }.uniq
  end

  def test_intact_install_core_run_is_pass
    build_intact_install
    # Complete the rest of the liveness surface so nothing else fails.
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    write_agents(DOCTOR_TEST_CLAUDE)
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "1.0.0")
    write_core_scripts(File.join(DOCTOR_TEST_HOME, "scripts"))
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump("projects" => {}))
    File.write(File.join(DOCTOR_TEST_HOME, "INDEX.md"), "# Index\n")

    result = doctor.run_core_checks("claude")
    assert_equal "pass", result[:status],
      "non-pass checks: #{result[:checks].reject { |c| c[:status] == "pass" }.map { |c| [c[:name], c[:status], c[:message]] }}"
  end

  def test_tampered_file_fails
    paths = build_intact_install
    File.write(paths[:global_file], "# Plastic TAMPERED\n")

    checks = doctor.check_manifest_sync("claude")
    assert checks.any? { |c| c[:status] == "fail" }, "tampered file should fail"
    fail_check = checks.find { |c| c[:status] == "fail" }
    assert fail_check[:details].any? { |d| d.include?("PLASTIC.md") }
  end

  def test_deleted_file_fails
    paths = build_intact_install
    File.delete(paths[:agent_file])

    checks = doctor.check_manifest_sync("claude")
    assert checks.any? { |c| c[:status] == "fail" }, "deleted file should fail"
    fail_check = checks.find { |c| c[:status] == "fail" }
    assert fail_check[:details].any? { |d| d.include?("VERSION") }
  end

  def test_missing_manifest_fails
    # No manifest files written at all.
    checks = doctor.check_manifest_sync("claude")
    assert checks.any? { |c| c[:status] == "fail" }
    assert checks.any? { |c| c[:message].include?("manifest missing") }
  end

  def test_other_agent_uses_the_uniform_plastic_manifest_path
    # codex agent reads <dir>/plastic/manifest.json (intent 210, D2: same rule as claude)
    FileUtils.mkdir_p(DOCTOR_TEST_CODEX)
    global_file, global_hash = write_tracked(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"), "# Plastic\n")
    write_manifest(File.join(DOCTOR_TEST_HOME, "manifest.json"), { global_file => global_hash })

    agent_file, agent_hash = write_tracked(File.join(DOCTOR_TEST_CODEX, "skills", "x.md"), "# x\n")
    write_manifest(File.join(DOCTOR_TEST_CODEX, "plastic", "manifest.json"), { agent_file => agent_hash })

    checks = doctor.check_manifest_sync("codex")
    assert checks.all? { |c| c[:status] == "pass" },
      "Expected all pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  ensure
    FileUtils.rm_rf(DOCTOR_TEST_CODEX)
  end

  def test_codex_legacy_flat_manifest_path_is_no_longer_read
    # A leftover pre-migration <dir>/plastic-manifest.json must NOT satisfy the agent
    # manifest check once the uniform path is in effect (intent 210, D2 falsifiable check).
    FileUtils.mkdir_p(DOCTOR_TEST_CODEX)
    global_file, global_hash = write_tracked(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"), "# Plastic\n")
    write_manifest(File.join(DOCTOR_TEST_HOME, "manifest.json"), { global_file => global_hash })

    agent_file, agent_hash = write_tracked(File.join(DOCTOR_TEST_CODEX, "skills", "x.md"), "# x\n")
    write_manifest(File.join(DOCTOR_TEST_CODEX, "plastic-manifest.json"), { agent_file => agent_hash })

    checks = doctor.check_manifest_sync("codex")
    assert checks.any? { |c| c[:status] == "fail" },
      "the legacy flat manifest must not be treated as the agent manifest"
  ensure
    FileUtils.rm_rf(DOCTOR_TEST_CODEX)
  end

  # --- install_integrity (intent 210, D4/G6): FULL tier only, warn-only, never writes ---

  def test_install_integrity_passes_on_a_clean_install
    build_intact_install

    checks = doctor.check_install_integrity
    claude_check = checks.find { |c| c[:name] == "claude_integrity" }

    refute_nil claude_check
    assert_equal "pass", claude_check[:status]
  end

  def test_install_integrity_warns_on_a_hand_edited_tracked_file
    paths = build_intact_install
    File.write(paths[:agent_file], "1.0.0-HAND-EDITED")

    checks = doctor.check_install_integrity
    claude_check = checks.find { |c| c[:name] == "claude_integrity" }

    assert_equal "warn", claude_check[:status]
    assert_includes claude_check[:details], tilde_expected(paths[:agent_file])
  end

  def tilde_expected(path)
    doctor.tilde(path)
  end

  # Falsifiable (AC9): install_integrity never writes, even when it finds drift.
  def test_install_integrity_never_writes
    paths = build_intact_install
    File.write(paths[:agent_file], "1.0.0-HAND-EDITED")
    manifest_path = File.join(DOCTOR_TEST_CLAUDE, "plastic", "manifest.json")
    before_manifest_mtime = File.mtime(manifest_path)
    before_agent_mtime = File.mtime(paths[:agent_file])

    doctor.check_install_integrity

    assert_equal before_manifest_mtime, File.mtime(manifest_path), "install_integrity must never write the manifest"
    assert_equal before_agent_mtime, File.mtime(paths[:agent_file]), "install_integrity must never write a tracked file"
  end

  # AC9, falsifiable: install_integrity is FULL-tier only, never part of the binary core run.
  def test_install_integrity_is_full_tier_only_absent_from_core_run
    build_intact_install
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    write_agents(DOCTOR_TEST_CLAUDE)
    write_core_scripts(File.join(DOCTOR_TEST_HOME, "scripts"))
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "1.0.0")
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump("projects" => {}))
    File.write(File.join(DOCTOR_TEST_HOME, "INDEX.md"), "# Index\n")

    core_names = doctor.run_core_checks("claude")[:checks].map { |c| c[:name] }
    full_names = doctor.run_checks("claude")[:checks].map { |c| c[:name] }

    refute_includes core_names, "claude_integrity", "install_integrity must be absent from the binary core run"
    assert_includes full_names, "claude_integrity", "install_integrity must be present in the full run"
  end

  # --- binary roll-up ---

  def test_binary_summarize_warn_rolls_up_to_fail
    warn_check = doctor.check(category: "x", name: "w", status: "warn", message: "m")
    pass_check = doctor.check(category: "x", name: "p", status: "pass", message: "m")

    result = doctor.summarize([warn_check, pass_check], "claude", binary: true)
    assert_equal "fail", result[:status], "binary roll-up: any warn must become fail"
  end

  def test_binary_summarize_never_emits_warn
    warn_check = doctor.check(category: "x", name: "w", status: "warn", message: "m")
    result = doctor.summarize([warn_check], "claude", binary: true)
    refute_equal "warn", result[:status]
  end

  def test_binary_summarize_all_pass_is_pass
    pass_check = doctor.check(category: "x", name: "p", status: "pass", message: "m")
    result = doctor.summarize([pass_check], "claude", binary: true)
    assert_equal "pass", result[:status]
  end

  def test_three_state_summarize_unchanged_default
    warn_check = doctor.check(category: "x", name: "w", status: "warn", message: "m")
    result = doctor.summarize([warn_check], "claude")
    assert_equal "warn", result[:status], "non-binary summarize keeps 3-state"
  end

  def test_version_mismatch_warn_rolls_up_to_fail_in_core
    # Build matching manifests, complete liveness, then force a version_match warn.
    build_intact_install
    write_claude_hooks(File.join(DOCTOR_TEST_CLAUDE, "hooks"))
    write_claude_settings(File.join(DOCTOR_TEST_CLAUDE, "settings.json"))
    write_skills(DOCTOR_TEST_CLAUDE)
    write_agents(DOCTOR_TEST_CLAUDE)
    write_core_scripts(File.join(DOCTOR_TEST_HOME, "scripts"))
    # global VERSION 2.0.0 vs agent-side plastic/VERSION 1.0.0 (from build_intact_install)
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "2.0.0")
    File.write(File.join(DOCTOR_TEST_HOME, "projects.yml"), YAML.dump("projects" => {}))
    File.write(File.join(DOCTOR_TEST_HOME, "INDEX.md"), "# Index\n")

    result = doctor.run_core_checks("claude")
    assert_equal "warn", result[:checks].find { |c| c[:name] == "version_match" }&.dig(:status),
      "precondition: version_match should warn"
    assert_equal "fail", result[:status], "a warn must roll up to fail in --core"
  end
end

# ===========================================================================
# Task C (intent 170) - agent_model_drift: config-vs-frontmatter advisory check
# ===========================================================================

class DoctorAgentModelDriftTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf([DOCTOR_TEST_HOME, DOCTOR_TEST_CLAUDE])
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_CLAUDE)
  end

  def teardown
    FileUtils.rm_rf([DOCTOR_TEST_HOME, DOCTOR_TEST_CLAUDE])
  end

  # Write an installed agent role file with an explicit frontmatter `model:`.
  def write_agent_file(agent_dir, basename, model:)
    agents_dir = File.join(agent_dir, "agents")
    FileUtils.mkdir_p(agents_dir)
    path = File.join(agents_dir, "#{basename}.md")
    File.write(path, <<~MD)
      ---
      name: #{basename}
      description: test fixture
      model: #{model}
      ---
      # #{basename}
    MD
    path
  end

  def write_global_config(overrides)
    File.write(File.join(DOCTOR_TEST_HOME, "config.yml"), YAML.dump(
      "agents" => { "models" => overrides }
    ))
  end

  def test_drift_warns_when_unconfigured_frontmatter_disagrees_with_default
    default = AgentModels::TIER_DEFAULTS["plastic-executor"]
    refute_equal "haiku", default, "fixture assumes plastic-executor's shipped default isn't haiku"
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-executor", model: "haiku")
    # No config.yml at all -> no override configured for plastic-executor.

    checks = doctor.check_agent_model_drift("claude")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "warn", drift_check[:status]
    assert drift_check[:details].any? { |d| d.include?("plastic-executor") },
      "expected drift details to name plastic-executor, got: #{drift_check[:details].inspect}"
  end

  def test_sanctioned_override_is_listed_as_pass_even_when_frontmatter_differs
    default = AgentModels::TIER_DEFAULTS["plastic-executor"]
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-executor", model: default)
    # Sanctioned override differs from both the shipped default and the
    # installed frontmatter (mirrors the real ~/.plastic/config.yml override,
    # mihradesign intent 24: plastic-executor -> fable).
    write_global_config("plastic-executor" => "fable")

    checks = doctor.check_agent_model_drift("claude")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "pass", drift_check[:status],
      "a sanctioned override must never be flagged, even if frontmatter has not caught up yet"
    assert drift_check[:details].any? { |d| d.include?("plastic-executor") && d.include?("fable") },
      "expected the sanctioned override to be LISTED, got: #{drift_check[:details].inspect}"
  end

  def test_clean_match_passes
    default = AgentModels::TIER_DEFAULTS["plastic-executor"]
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-executor", model: default)
    # No config.yml -> no override; frontmatter already matches the default.

    checks = doctor.check_agent_model_drift("claude")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "pass", drift_check[:status]
  end

  def test_no_installed_agent_files_passes
    # DOCTOR_TEST_CLAUDE has no agents/ dir at all.
    checks = doctor.check_agent_model_drift("claude")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "pass", drift_check[:status]
  end

  def test_check_never_returns_fail
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-executor", model: "totally-unresolved-model")

    checks = doctor.check_agent_model_drift("claude")

    refute checks.any? { |c| c[:status] == "fail" },
      "agent_model_drift must never fail the run, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  end

  def test_wired_into_check_core_files
    build_core_files_for_drift
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-executor", model: "haiku")

    checks = doctor.check_core_files("claude")

    assert checks.any? { |c| c[:name] == "agent_model_drift" },
      "check_core_files must include the agent_model_drift check"
  end

  def test_consultation_agent_with_shipped_default_never_flagged_as_drift
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-advisor", model: "fable")
    # No config.yml -> no override configured for plastic-advisor.

    checks = doctor.check_agent_model_drift("claude")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "pass", drift_check[:status],
      "a consultation agent must never be flagged as drift; its model is user configuration"
    assert drift_check[:details].any? { |d| d.include?("plastic-advisor") && d.include?("consultation") },
      "expected plastic-advisor to be listed informationally as a consultation role, got: #{drift_check[:details].inspect}"
  end

  def test_consultation_agent_model_change_is_still_not_flagged_as_drift
    # plastic-advisor ships fable by default; installing it with a DIFFERENT
    # model and no override must still never be treated as drift, because
    # bucket 3 never compares a consultation agent's frontmatter to anything.
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-advisor", model: "opus")

    checks = doctor.check_agent_model_drift("claude")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    assert_equal "pass", drift_check[:status]
    refute drift_check[:details].any? { |d| d.include?("resolved default") },
      "a consultation agent must never be compared against a resolved default"
  end

  def test_unclassified_agent_warns_naming_agent_models_rb
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-not-a-real-role", model: "sonnet")
    # No config.yml -> no override; basename is in neither registry.

    checks = doctor.check_agent_model_drift("claude")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    refute_nil drift_check
    assert_equal "warn", drift_check[:status]
    assert drift_check[:details].any? { |d| d.include?("plastic-not-a-real-role") && d.include?("agent_models.rb") },
      "expected an actionable unclassified message naming agent_models.rb, got: #{drift_check[:details].inspect}"
  end

  def test_unclassified_agent_silenced_by_explicit_override
    write_agent_file(DOCTOR_TEST_CLAUDE, "plastic-not-a-real-role", model: "sonnet")
    write_global_config("plastic-not-a-real-role" => "sonnet")

    checks = doctor.check_agent_model_drift("claude")
    drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

    assert_equal "pass", drift_check[:status],
      "an explicit agents.models.<name> override must silence the unclassified warning too"
    assert drift_check[:details].any? { |d| d.include?("plastic-not-a-real-role") && d.include?("sanctioned override") }
  end

  # End-to-end regression proof (intent 191): the REAL shipped agents/*.md
  # roster, with no config.yml override, must produce zero drift and zero
  # unclassified entries through the actual check_agent_model_drift code
  # path, not a synthetic fixture. This is the direct proof that today's
  # false positive (both advisors reported as drift) is gone and cannot
  # silently come back.
  def test_real_shipped_agent_roster_has_zero_drift_and_zero_unclassified
    worktree = File.expand_path("../../", __FILE__)
    real_home = Dir.mktmpdir("plastic-doctor-real-roster")
    begin
      real_doctor = Doctor.new(
        plastic_home: real_home,
        agents: { "claude" => { name: "Claude Code", dir: worktree } }
      )
      # No config.yml in real_home -> no overrides configured for anything.

      checks = real_doctor.check_agent_model_drift("claude")
      drift_check = checks.find { |c| c[:name] == "agent_model_drift" }

      refute_nil drift_check
      assert_equal "pass", drift_check[:status],
        "the real shipped agents/*.md roster must classify cleanly with no config overrides: " \
        "#{drift_check[:message]} #{drift_check[:details].inspect}"
      refute drift_check[:details].any? { |d| d.include?("resolved default=nil") },
        "no agent should ever be reported with a nil resolved default"
    ensure
      FileUtils.rm_rf(real_home)
    end
  end

  private

  def build_core_files_for_drift
    File.write(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"), "# Plastic\n")
    File.write(File.join(DOCTOR_TEST_HOME, "VERSION"), "1.0.0")
    write_core_scripts(File.join(DOCTOR_TEST_HOME, "scripts"))
    agent_version_dir = File.join(DOCTOR_TEST_CLAUDE, "plastic")
    FileUtils.mkdir_p(agent_version_dir)
    File.write(File.join(agent_version_dir, "VERSION"), "1.0.0")
  end
end
