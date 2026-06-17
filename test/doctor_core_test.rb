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

  def test_core_run_is_exactly_the_three_liveness_groups
    d = doctor
    expected = (d.check_agent_registration("claude") +
                d.check_core_files("claude") +
                d.check_manifest_sync("claude"))
               .map { |c| c[:name] }
    actual = d.run_core_checks("claude")[:checks].map { |c| c[:name] }

    assert_equal expected, actual,
      "--core must be exactly agent_registration + core_files + manifest_sync, in order"
  end

  def test_core_run_only_has_liveness_categories
    result = doctor.run_core_checks("claude")
    categories = result[:checks].map { |c| c[:category] }.uniq

    assert_equal %w[agent_registration core_files manifest_sync], categories.sort,
      "--core categories should be agent_registration, core_files, and manifest_sync"
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

    %w[global_store conventions project_stores deprecations].each do |cat|
      assert_includes categories, cat, "full doctor must still run '#{cat}' category"
    end
  end

  def test_core_liveness_checks_are_subset_of_full_run
    # manifest_sync is core-only; the rest of --core must also appear in the
    # full run.
    manifest_names = doctor.check_manifest_sync("claude").map { |c| c[:name] }
    core_names = doctor.run_core_checks("claude")[:checks].map { |c| c[:name] }
    full_names = doctor.run_checks("claude")[:checks].map { |c| c[:name] }

    extra = (core_names - manifest_names) - full_names
    assert_empty extra, "non-manifest core checks not present in full run: #{extra.inspect}"
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

  def test_other_agent_uses_flat_manifest_path
    # codex agent reads <dir>/plastic-manifest.json
    FileUtils.mkdir_p(DOCTOR_TEST_CODEX)
    global_file, global_hash = write_tracked(File.join(DOCTOR_TEST_HOME, "PLASTIC.md"), "# Plastic\n")
    write_manifest(File.join(DOCTOR_TEST_HOME, "manifest.json"), { global_file => global_hash })

    agent_file, agent_hash = write_tracked(File.join(DOCTOR_TEST_CODEX, "skills", "x.md"), "# x\n")
    write_manifest(File.join(DOCTOR_TEST_CODEX, "plastic-manifest.json"), { agent_file => agent_hash })

    checks = doctor.check_manifest_sync("codex")
    assert checks.all? { |c| c[:status] == "pass" },
      "Expected all pass, got: #{checks.map { |c| [c[:name], c[:status]] }}"
  ensure
    FileUtils.rm_rf(DOCTOR_TEST_CODEX)
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

    result = doctor.run_core_checks("claude")
    assert_equal "warn", result[:checks].find { |c| c[:name] == "version_match" }&.dig(:status),
      "precondition: version_match should warn"
    assert_equal "fail", result[:status], "a warn must roll up to fail in --core"
  end
end
