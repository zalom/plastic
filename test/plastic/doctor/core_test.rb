# frozen_string_literal: true

require_relative "whole_home"
require_relative "../../../scripts/lib/plastic/doctor"

class DoctorCoreTest < Plastic::TestCase
  include WholeHome

  def setup
    super
    whole_home
  end

  def checks(running: RUNNING, loader: -> { "2.0.0" }) = Plastic::Doctor::Core.new(scope, running:, loader:).checks

  def check(label, **options) = checks(**options).find { |item| item.label == label }

  def test_a_whole_home_has_no_finding
    assert_empty checks.filter_map(&:repair), checks.map(&:to_h).inspect
  end

  def test_every_check_that_passes_says_ok
    assert_empty(checks.reject(&:repair).reject { |item| item.value.start_with?("ok, ") })
  end

  def test_a_stale_version_record_names_the_reinstall
    version = check("version:", running: "9.2.0")

    assert_equal ["9.2.0 runs, but #{File.join(@plastic_home, "VERSION")} records #{RUNNING}", "plastic install --reinstall"],
      [version.value, version.repair]
  end

  def test_a_missing_version_record_names_the_install
    File.delete(File.join(@plastic_home, "VERSION"))

    assert_equal "plastic install", check("version:").repair
  end

  def test_a_sqlite3_gem_that_does_not_load_is_a_finding
    sqlite = check("sqlite3 gem:", loader: -> { raise LoadError, "cannot load such file -- sqlite3" })

    assert_equal ["does not load: cannot load such file -- sqlite3", "gem install sqlite3"], [sqlite.value, sqlite.repair]
  end

  def test_the_machine_database_is_named_from_the_schema_catalog
    label = "#{schema.file(machine_key)}:"

    assert_equal "ok, every table present", check(label).value
  end

  def test_a_missing_machine_database_names_the_command_that_makes_it
    File.delete(machine_path)
    database = check("#{schema.file(machine_key)}:")

    assert_equal ["#{machine_path} is missing", "plastic install --reinstall"], [database.value, database.repair]
  end

  def test_a_store_that_lacks_a_table_names_the_table_and_the_repair
    drop_table(store_path(:work), "intents")
    store = check("store #{SLUG}:")

    assert_equal ["work_graph.db lacks the table intents", "plastic project new #{SLUG} #{project_dir}"], [store.value, store.repair]
  end

  def test_a_store_with_no_folder_names_each_database
    FileUtils.rm_rf(store_dir)

    assert_equal 3, check("store #{SLUG}:").value.scan("is missing").size
  end

  def test_a_missing_plastic_md_names_the_reinstall
    File.delete(File.join(@plastic_home, "PLASTIC.md"))

    assert_equal "plastic install --reinstall", check("PLASTIC.md:").repair
  end

  def test_a_project_agents_md_without_the_plastic_line_names_the_edit
    agents = File.join(project_dir, "AGENTS.md")
    File.write(agents, "# Alpha\n")

    assert_equal "add a line naming ~/.plastic/PLASTIC.md to #{agents}", check("AGENTS.md #{SLUG}:").repair
  end

  def test_the_checks_change_no_file
    before = Dir.glob("**/*", File::FNM_DOTMATCH, base: @home).sort
    checks

    assert_equal before, Dir.glob("**/*", File::FNM_DOTMATCH, base: @home).sort
  end
end
