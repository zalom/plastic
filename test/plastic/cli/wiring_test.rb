# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/cli/wiring"

class WiringTest < Plastic::TestCase
  include ConfigHomes

  SyncSelection = Plastic::Graph::Knowledge::SyncSelection

  PATHS = %w[spec.md resources/shot.PNG resources/demo.mp4 resources/page.html .hidden references/notes.md references/paper.pdf].freeze

  def read_by(selection) = PATHS.select { |rel| selection.read?(rel) }

  def test_a_home_with_no_setting_reads_no_optional_kind
    assert_equal read_by(SyncSelection.none), read_by(Plastic::Wiring.selection(@plastic_home))
  end

  def test_the_media_setting_adds_the_images_and_videos_and_nothing_else
    seed_config(@plastic_home, "global:\n  sync:\n    media: true\n")

    assert_equal %w[resources/shot.PNG resources/demo.mp4], read_by(Plastic::Wiring.selection(@plastic_home)) - read_by(SyncSelection.none)
  end

  def test_the_documents_and_references_settings_add_their_own_kinds
    seed_config(@plastic_home, "global:\n  sync:\n    documents: true\n    references: true\n")

    assert_equal %w[resources/page.html .hidden references/notes.md references/paper.pdf],
      read_by(Plastic::Wiring.selection(@plastic_home)) - read_by(SyncSelection.none)
  end

  def test_the_graphs_carry_the_selection_and_the_import_cleanup_flag_of_the_home
    seed_config(@plastic_home, "global:\n  sync:\n    media: true\n  migrate:\n    remove_after_import: true\n")
    sync = Plastic::Wiring.sync(@plastic_home)

    assert sync.selection.read?("resources/shot.PNG")
    assert sync.remove_after_import
  end

  def test_the_graphs_of_a_home_with_no_setting_remove_nothing_after_an_import
    sync = Plastic::Wiring.sync(@plastic_home)

    refute sync.remove_after_import
  end

  def test_the_graphs_open_with_the_sync_settings_of_the_home
    seed_config(@plastic_home, "global:\n  sync:\n    media: true\n")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "global"))
    graphs = Plastic::Wiring.graphs(home: @plastic_home, store: "global")

    assert_instance_of Plastic::Graph::WorkGraph, graphs.work
    assert Plastic::Wiring.sync(@plastic_home).selection.read?("resources/shot.PNG")
  end

  def test_the_config_reads_the_rows_of_the_home_and_the_store_writes_them
    seed_config(@plastic_home, "global:\n  screens: false\n")
    Plastic::Wiring.store(@plastic_home).set("global", "screens", true)

    assert Plastic::Wiring.config(@plastic_home).value("screens")
    assert_equal({ "screens" => true }, Plastic::Wiring.rows(@plastic_home).scope("global"))
  end
end
