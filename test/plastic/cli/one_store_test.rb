# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/store/backup"
require_relative "../../../lib/plastic/commands/store/backup/restore"

class CLIOneStoreTest < Plastic::TestCase
  include BackupHomes

  def test_a_call_without_a_project_refuses_and_says_to_name_the_store
    assert_refused_with_usage restore_call(fresh_home, "--latest"), "name the store with --project"
  end

  def test_an_unregistered_store_refuses_and_names_it
    assert_refused_with_usage restore_call(fresh_home, "--project", "nowhere", "--latest"), "nowhere"
  end

  def test_a_call_with_neither_of_two_exclusive_options_says_which_to_give
    assert_refused_with_usage restore_call(fresh_home, "--project", "alpha"), "give --timestamp TS or --latest"
  end

  def test_a_call_with_both_of_two_exclusive_options_says_they_exclude_each_other
    assert_refused_with_usage restore_call(fresh_home, "--project", "alpha", "--latest", "--timestamp", "20260101100000"), "exclude each other"
  end

  def test_an_unknown_database_name_refuses_as_a_usage_error
    assert_refused_with_usage restore_call(fresh_home, "--project", "alpha", "--latest", "--databases", "nope"), "nope"
  end
end
