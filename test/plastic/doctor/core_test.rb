# frozen_string_literal: true

require_relative "whole_home"
require_relative "../../../lib/plastic/doctor"

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
    refute_includes database.repair, "plastic next"
  end

  def test_a_store_that_lacks_a_table_names_the_table_and_the_repair
    drop_table(store_path(:knowledge), "intents")
    store = check("store #{SLUG}:")

    assert_equal ["knowledge_graph.db lacks the table intents", "plastic project new #{SLUG} #{project_dir}"], [store.value, store.repair]
  end

  def test_a_store_with_no_folder_names_each_database
    FileUtils.rm_rf(store_dir)

    assert_equal 2, check("store #{SLUG}:").value.scan("is missing").size
  end

  def test_a_missing_global_store_names_the_reinstall
    FileUtils.rm_rf(File.join(@plastic_home, "stores", "global"))
    global = check("global store:")

    assert_equal ["#{File.join(@plastic_home, "stores", "global")} is missing", "plastic install --reinstall"], [global.value, global.repair]
  end

  def test_a_present_global_store_says_ok
    assert_nil check("global store:").repair
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

  def test_the_checks_change_no_file_but_the_home_gitignore
    checks
    before = Dir.glob("**/*", File::FNM_DOTMATCH, base: @home).sort
    checks

    assert_equal before, Dir.glob("**/*", File::FNM_DOTMATCH, base: @home).sort
  end
end

class DoctorHomeFilesTest < Plastic::TestCase
  include WholeHome

  def setup
    super
    whole_home
  end

  def checks = Plastic::Doctor::Core.new(scope, running: RUNNING, loader: -> { "2.0.0" }).checks

  def check(label) = checks.find { |item| item.label == label }

  def gitignore = File.join(@plastic_home, ".gitignore")

  def test_the_home_gitignore_gets_the_database_line_when_it_lacks_it
    File.write(gitignore, "backups/\n")
    checks

    assert_equal ["backups/", "*.db", "*.db-*"], File.readlines(gitignore, chomp: true)
  end

  def test_a_home_with_no_gitignore_gets_one_with_the_database_line
    checks

    assert_equal ["*.db", "*.db-*"], File.readlines(gitignore, chomp: true)
  end

  def test_the_database_line_is_added_once
    checks
    checks

    assert_equal ["*.db", "*.db-*"], File.readlines(gitignore, chomp: true)
  end

  def test_the_gitignore_check_says_what_it_added
    assert_equal "ok, *.db *.db-* added", check(".gitignore:").value
  end

  def test_a_local_db_beside_plastic_db_is_a_finding_that_names_the_file
    File.write(File.join(@plastic_home, "local.db"), "left from before")
    found = check("local.db:")

    assert_equal ["#{File.join(@plastic_home, "local.db")} is left beside plastic.db", "move local.db out of #{@plastic_home}; plastic update keeps a copy of it in backups/"], [found.value, found.repair]
  end

  def test_a_config_file_edited_by_hand_after_the_print_is_a_finding_with_the_refusal_line
    Plastic::Config::Store.new(@plastic_home).set("global", "screens", false)
    File.write(File.join(@plastic_home, "config.yml"), "x: 1\n")
    found = check("config.yml:")

    assert_equal ["#{File.join(@plastic_home, "config.yml")} changed since it was printed from the settings; move it aside, then run plastic config set KEY VALUE to print it again", "plastic config set KEY VALUE"],
      [found.value, found.repair]
  end

  def test_a_config_file_printed_from_the_settings_is_ok
    Plastic::Config::Store.new(@plastic_home).set("global", "screens", false)

    assert_match(/\Aok, /, check("config.yml:").value)
  end

  def test_a_local_db_with_no_plastic_db_is_a_finding_that_names_plastic_update
    File.write(File.join(@plastic_home, "local.db"), "not migrated")
    File.delete(File.join(@plastic_home, "plastic.db"))
    found = check("local.db:")

    assert_equal ["#{File.join(@plastic_home, "local.db")} is not migrated", "plastic update"], [found.value, found.repair]
  end

  def test_a_home_with_no_local_db_has_no_local_db_check
    assert_nil check("local.db:")
  end
end
