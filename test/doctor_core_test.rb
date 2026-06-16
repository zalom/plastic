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

  def test_core_run_is_exactly_the_two_liveness_groups
    d = doctor
    expected = (d.check_agent_registration("claude") + d.check_core_files("claude"))
               .map { |c| c[:name] }
    actual = d.run_core_checks("claude")[:checks].map { |c| c[:name] }

    assert_equal expected, actual,
      "--core must be exactly agent_registration + core_files, in order"
  end

  def test_core_run_only_has_liveness_categories
    result = doctor.run_core_checks("claude")
    categories = result[:checks].map { |c| c[:category] }.uniq

    assert_equal %w[agent_registration core_files], categories.sort,
      "--core categories should be only agent_registration and core_files"
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

  def test_core_run_is_subset_of_full_run
    core_names = doctor.run_core_checks("claude")[:checks].map { |c| c[:name] }
    full_names = doctor.run_checks("claude")[:checks].map { |c| c[:name] }

    extra = core_names - full_names
    assert_empty extra, "core checks not present in full run: #{extra.inspect}"
  end
end
