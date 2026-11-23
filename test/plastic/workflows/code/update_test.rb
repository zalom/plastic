# frozen_string_literal: true

require_relative "../../commands/installer_helper"
require_relative "../../../../lib/plastic/workflows/code/update"

class UpdatePlasticTest < Plastic::TestCase
  include InstallerHelper
  include BackupHomes
  include OldLayoutHomes
  include ConfigHomes

  # The store versions an update applies while every switch is off.
  RUNNABLE = Plastic::Graph::MIGRATIONS.versions(:store) - Plastic::Graph::MIGRATIONS.held(:store)

  def update(env: {}, **options)
    facts = { channel: nil }.merge(options)
    run_workflow(Plastic::Workflows::Code::Update, harness: scoped_harness(env: { "PLASTIC_SHARE" => share }.merge(env)), **facts)
  end

  def store_versions(home) = recorded_by_file(home).select { |path, _| path.end_with?("/knowledge_graph.db") }.values.uniq

  # Every store and the home as an alpha build wrote them: the newest layout, stamped 1, with no schema_migrations table.
  def alpha_layout(home)
    Plastic::Graph::Database::ConnectionPool.release(home)
    Dir.glob(File.join(home, "{plastic.db,stores/*/knowledge_graph.db}")).each do |path|
      SQLite3::Database.open(path) { |db| db.execute_batch("DROP TABLE schema_migrations; PRAGMA user_version = 1") }
    end
    Dir.glob(File.join(home, "stores/*/work_graph.db")).each do |path|
      SQLite3::Database.open(path) { |db| Plastic::Graph::RunUsageColumns::NAMES.each { |name| db.execute("ALTER TABLE runs DROP COLUMN #{name}") } }
    end
    home
  end

  def current(version) = { "PLASTIC_PACKAGE_ROOT" => fake_package(version) }

  def test_an_update_brings_an_old_layout_home_to_every_version_but_the_held_ones_after_a_backup_of_each_store
    home = old_layout(fresh_home)
    run_workflow(Plastic::Workflows::Code::Update, channel: nil, harness: scoped_harness(env: env_for(home).merge("PLASTIC_SHARE" => share)))

    assert_equal [RUNNABLE], store_versions(home)
    assert_equal [1, 1], %w[alpha beta].map { |slug| folder_names(home, slug).size }
  end

  def test_an_update_moves_an_alpha_home_and_its_stores_from_stamp_1_to_every_version_but_the_held_ones
    home = alpha_layout(fresh_home)
    run_workflow(Plastic::Workflows::Code::Update, channel: nil, harness: scoped_harness(env: env_for(home).merge("PLASTIC_SHARE" => share)))
    Plastic::Graph::Database::ConnectionPool.release(home)

    assert_equal [RUNNABLE, Plastic::Graph::MIGRATIONS.versions(:home)], [store_versions(home).flatten.uniq, recorded_versions(File.join(home, "plastic.db"))]
  end

  PAPER = "store/1--a/resources/references/paper.pdf"

  def alpha_knowledge(home) = File.join(home, "stores", "alpha", "knowledge_graph.db")

  # A home that reads references, whose alpha store lacks the newest version and keeps the file PAPER.
  def home_reading_references
    home = fresh_home
    seed_config(home, "global:\n  sync:\n    references: true\n")
    Plastic::Graph::Database::ConnectionPool.release(home)
    SQLite3::Database.open(alpha_knowledge(home)) do |database|
      database.execute("DELETE FROM schema_migrations WHERE version = ?", [Plastic::Graph::MIGRATIONS.newest(:store)])
      database.execute("INSERT INTO sqlar (name, mode, mtime, sz, data, origin_id) VALUES (?, 420, 0, 0, x'00', 'o')", [PAPER])
    end
    SQLite3::Database.open(File.join(home, "stores", "alpha", "work_graph.db")) { |db| Plastic::Graph::RunUsageColumns::NAMES.each { |name| db.execute("ALTER TABLE runs DROP COLUMN #{name}") } }
    home
  end

  def test_an_update_keeps_a_kept_file_the_sync_settings_of_the_machine_read
    home = home_reading_references
    run_workflow(Plastic::Workflows::Code::Update, channel: nil,
      harness: scoped_harness(env: env_for(home).merge("PLASTIC_SHARE" => share), settings: Plastic::Wiring.settings(home)))
    Plastic::Graph::Database::ConnectionPool.release(home)

    assert_equal [[PAPER]], SQLite3::Database.open(alpha_knowledge(home)) { |database| database.execute("SELECT name FROM sqlar") }
  end

  def test_a_newer_package_is_synced_into_the_home
    installed("0.0.1")

    outcome, = update

    assert_equal :done, outcome
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
  end

  def test_with_no_release_activated_it_names_install_sh_and_no_channel_variable
    installed("99.0.0-alpha.1")

    outcome, context = update(env: current("99.0.0-alpha.1"))

    assert_equal :fetch, outcome
    assert_equal "#{Plastic::Workflows::Installation::INSTALLER} sh", printed_row(context, "run:")
  end

  def test_a_newer_release_on_the_channel_is_downloaded_and_the_install_command_named
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    env = current("99.0.0-alpha.1").merge("PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.2"))

    outcome, context = update(env:)

    assert_equal [:downloaded, "99.0.0-alpha.2"], [outcome, context.release]
    assert_equal "99.0.0-alpha.1", activation.active_version
    assert_includes context.command, "--version 99.0.0-alpha.2"
  end

  def test_a_home_with_only_a_release_from_install_sh_syncs_nothing_and_checks_for_a_newer_release
    activated("99.0.0-alpha.1")
    env = current("99.0.0-alpha.1").merge("PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.2"))

    outcome, = update(env:)

    assert_equal [:downloaded, false], [outcome, File.exist?(File.join(@plastic_home, "VERSION"))]
  end

  def test_the_newest_active_release_stays_current
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    env = current("99.0.0-alpha.1").merge("PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.1"))

    outcome, = update(env:)

    assert_equal [:current, ["99.0.0-alpha.1"]], [outcome, activation.releases.versions]
  end
end
