# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/config"

class ConfigStoreTest < Plastic::TestCase
  include ConfigHomes

  def store = Plastic::Config::Store.new(@plastic_home)

  def path = File.join(@plastic_home, "config.yml")

  def test_a_setting_is_written_as_a_row_and_the_file_is_printed_from_the_rows
    store.set("global", "runner.stop_hook", true)

    assert_equal [["global", "runner.stop_hook", "true"]], setting_rows(@plastic_home)
    assert_equal({ "version" => 3, "global" => { "runner" => { "stop_hook" => true } } }, YAML.safe_load_file(path))
  end

  def test_the_printed_file_has_no_anchors
    store.set("global", "agents.models.a", "haiku")
    store.set("claude-code", "agents.models.a", "haiku")

    refute_match(/[&*]\d|<</, File.read(path))
  end

  def test_the_same_rows_print_the_same_bytes
    store.set("global", "screens", false)
    first = File.read(path)
    store.print

    assert_equal first, File.read(path)
  end

  def test_a_setting_of_a_harness_prints_under_harnesses_and_an_empty_global_is_left_out
    store.set("codex", "screens", false)

    assert_equal({ "version" => 3, "harnesses" => { "codex" => { "screens" => false } } }, YAML.safe_load_file(path))
  end

  def test_a_file_changed_by_hand_after_the_print_is_refused_with_the_line_that_names_the_fix
    store.set("global", "screens", false)
    File.write(path, "global:\n  screens: true\n")
    error = assert_raises(Plastic::CLI::Command::Refusal) { store.set("global", "statusline", true) }

    assert_equal "#{path} changed since it was printed from the settings; move it aside, then run plastic config set KEY VALUE to print it again", error.message
    assert_equal [["global", "screens", "false"]], setting_rows(@plastic_home)
  end

  def test_a_hand_edited_file_that_is_moved_aside_is_printed_again_by_the_next_set
    store.set("global", "screens", false)
    File.write(path, "global:\n  screens: true\n")
    File.rename(path, "#{path}.mine")
    store.set("global", "statusline", true)

    assert_equal({ "screens" => false, "statusline" => true }, YAML.safe_load_file(path).fetch("global"))
  end

  def test_the_hand_edit_line_never_sends_the_person_to_sync_up
    store.set("global", "screens", false)
    File.write(path, "x: 1\n")
    error = assert_raises(Plastic::CLI::Command::Refusal) { store.set("global", "statusline", true) }

    refute_includes error.message, "sync up"
  end
end
