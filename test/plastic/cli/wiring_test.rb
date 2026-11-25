# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/cli/wiring"

class WiringTest < Plastic::TestCase
  include ConfigHomes

  SyncSelection = Plastic::Graph::Knowledge::SyncSelection

  PATHS = %w[spec.md resources/output/reports/page.md resources/output/files/shot.png resources/output/files/page.html resources/references/paper.pdf resources/tmp/scratch.md].freeze

  def read_by(selection) = PATHS.select { |rel| selection.read?(rel) }

  def test_a_home_with_no_setting_reads_the_markdown_and_html_types_no_report_and_no_references
    assert_equal %w[spec.md resources/output/files/page.html], read_by(Plastic::Wiring.selection(@plastic_home))
  end

  def test_a_home_with_no_setting_has_no_mandatory_report
    assert_empty Plastic::Config::Defaults::GLOBAL.fetch("reports").fetch("mandatory")
  end

  def test_the_mandatory_setting_names_the_reports_read_in_every_intent
    seed_config(@plastic_home, "global:\n  reports:\n    mandatory: [page.md]\n")

    assert_includes read_by(Plastic::Wiring.selection(@plastic_home)), "resources/output/reports/page.md"
  end

  def test_the_types_setting_names_the_types_read
    seed_config(@plastic_home, "global:\n  sync:\n    types: [png]\n")

    assert_equal %w[spec.md resources/output/files/shot.png], read_by(Plastic::Wiring.selection(@plastic_home))
  end

  def test_the_types_setting_given_as_a_comma_value_is_read_as_a_list
    seed_config(@plastic_home, "global:\n  sync:\n    types: md,png\n")

    assert_equal %w[spec.md resources/output/files/shot.png], read_by(Plastic::Wiring.selection(@plastic_home))
  end

  def test_the_references_setting_adds_the_references_folder
    seed_config(@plastic_home, "global:\n  sync:\n    references: true\n")

    assert_includes read_by(Plastic::Wiring.selection(@plastic_home)), "resources/references/paper.pdf"
  end

  def test_the_settings_answer_the_selection_of_the_sync_settings_of_the_home
    seed_config(@plastic_home, "global:\n  sync:\n    types: [png]\n    references: true\n")

    assert_equal %w[spec.md resources/output/files/shot.png resources/references/paper.pdf], read_by(Plastic::Wiring.settings(@plastic_home).selection)
  end

  def test_the_asked_setting_is_carried_to_the_selection
    seed_config(@plastic_home, "global:\n  sync:\n    asked: [pdf]\n")

    assert_empty Plastic::Wiring.selection(@plastic_home).new_types(%w[resources/output/files/a.pdf])
  end

  def test_the_graphs_carry_the_selection_and_the_import_cleanup_flag_of_the_home
    seed_config(@plastic_home, "global:\n  sync:\n    types: [png]\n  migrate:\n    remove_after_import: true\n")
    sync = Plastic::Wiring.sync(@plastic_home)

    assert sync.selection.read?("resources/output/files/shot.PNG")
    assert sync.remove_after_import
  end

  def test_the_graphs_of_a_home_with_no_setting_remove_nothing_after_an_import
    sync = Plastic::Wiring.sync(@plastic_home)

    refute sync.remove_after_import
  end

  def test_the_graphs_open_with_the_sync_settings_of_the_home
    seed_config(@plastic_home, "global:\n  sync:\n    types: [png]\n")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "global"))
    graphs = Plastic::Wiring.graphs(home: @plastic_home, store: "global")

    assert_instance_of Plastic::Graph::GraphWriter, graphs.work
    assert Plastic::Wiring.sync(@plastic_home).selection.read?("resources/output/files/shot.PNG")
  end

  def test_the_config_reads_the_rows_of_the_home_and_the_store_writes_them
    seed_config(@plastic_home, "global:\n  screens: false\n")
    Plastic::Wiring.store(@plastic_home).set("global", "screens", true)

    assert Plastic::Wiring.config(@plastic_home).value("screens")
    assert_equal({ "screens" => true }, Plastic::Wiring.rows(@plastic_home).scope("global"))
  end

  def test_the_settings_answer_the_config_of_a_harness_and_the_store_of_the_home
    seed_config(@plastic_home, "harnesses:\n  claude-code:\n    statusline: true\n")
    settings = Plastic::Wiring.settings(@plastic_home)

    assert_equal [true, false], [settings.config(harness: "claude-code").flag(["statusline"], default: false), settings.config.flag(["statusline"], default: false)]
    assert_nil settings.store.problem
  end

  def test_a_home_with_no_setting_takes_no_daily_backups
    refute Plastic::Wiring.daily_backups?(@plastic_home)
  end

  def test_the_daily_setting_turns_the_daily_backups_on
    seed_config(@plastic_home, "global:\n  backup:\n    daily: true\n")

    assert Plastic::Wiring.daily_backups?(@plastic_home)
  end

  def test_every_store_has_the_store_lock
    assert_instance_of Plastic::StoreLock, Plastic::Wiring.store_lock(@plastic_home, "global")
  end

  def test_the_lock_waits_the_shipped_60_seconds
    assert_equal [60, 60], [Plastic::StoreLock::WAIT, Plastic::Wiring.lock_wait]
  end

  def test_a_lock_wait_set_through_the_seam_replaces_the_shipped_wait
    Plastic::Wiring.lock_wait = 0

    assert_equal 0, Plastic::Wiring.lock_wait
  ensure
    Plastic::Wiring.lock_wait = nil
  end
end
