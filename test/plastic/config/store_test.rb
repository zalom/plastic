# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/config"

class ConfigStoreTest < Plastic::TestCase
  include ConfigHomes

  def store = Plastic::Wiring.store(@plastic_home)

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
    error = assert_raises(Plastic::Config::HandEdited) { store.set("global", "statusline", true) }

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
    error = assert_raises(Plastic::Config::HandEdited) { store.set("global", "statusline", true) }

    refute_includes error.message, "sync up"
  end

  def test_the_first_print_copies_a_config_file_to_backups_first
    File.write(path, "global:\n  screens: false\n")
    store.print_once
    copies = Dir.glob(File.join(@plastic_home, "backups", "config-*.yml"))

    assert_equal ["global:\n  screens: false\n"], copies.map { |copy| File.read(copy) }
  end

  def test_a_config_file_that_does_not_parse_is_kept_and_one_line_is_returned
    File.write(path, "global: [unclosed\n")
    answer = store.print_once

    assert_equal ["global: [unclosed\n", true], [File.read(path), answer.start_with?("config.yml could not be read (")]
    assert_match(/\); fix it and run plastic update\z/, answer)
    assert_empty setting_rows(@plastic_home)
  end

  def test_a_config_file_that_is_a_bare_date_is_kept
    File.write(path, "2026-11-17\n")

    assert_match(/could not be read/, store.print_once)
    assert_equal "2026-11-17\n", File.read(path)
  end

  def test_a_config_file_that_is_a_list_is_kept_and_named_as_not_a_mapping
    File.write(path, "- a\n- b\n")

    assert_equal "config.yml could not be read (it is not a mapping); fix it and run plastic update", store.print_once
    assert_equal "- a\n- b\n", File.read(path)
  end

  def test_print_once_names_a_file_edited_by_hand_after_the_print
    store.set("global", "screens", false)
    File.write(path, "global:\n  screens: true\n")

    assert_equal "#{path} changed since it was printed from the settings; move it aside, then run plastic config set KEY VALUE to print it again", store.print_once
  end

  def test_print_once_of_an_untouched_printed_file_says_nothing
    store.set("global", "screens", false)

    assert_nil store.print_once
  end

  def test_the_problem_is_the_same_line_the_doctor_reports
    store.set("global", "screens", false)
    File.write(path, "x: 1\n")

    assert_equal store.print_once, store.problem
  end
end
