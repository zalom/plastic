# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/backup"
require_relative "../../../lib/plastic/commands/backup/restore"

class CLIBackupStoreTest < Plastic::TestCase
  include BackupHomes

  def test_a_call_naming_a_project_refuses_and_says_to_name_the_store
    assert_refused_with_usage restore_call(fresh_home, "--store", "alpha", "--project", "alpha", "--latest"), "--project does not apply"
  end

  def test_an_unregistered_store_refuses_and_lists_the_registered_ones
    assert_refused_with_usage restore_call(fresh_home, "--store", "nowhere", "--latest"), "the projects are alpha, beta"
  end

  def test_a_call_with_neither_of_two_exclusive_options_says_which_to_give
    assert_refused_with_usage restore_call(fresh_home, "--store", "alpha"), "give --timestamp TS or --latest"
  end

  def test_a_call_with_both_of_two_exclusive_options_says_they_exclude_each_other
    assert_refused_with_usage restore_call(fresh_home, "--store", "alpha", "--latest", "--timestamp", "20260101100000"), "exclude each other"
  end

  def test_an_unknown_database_name_refuses_as_a_usage_error
    assert_refused_with_usage restore_call(fresh_home, "--store", "alpha", "--latest", "--databases", "nope"), "nope"
  end
end
