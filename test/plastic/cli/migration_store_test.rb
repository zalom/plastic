# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/migration/down"
require_relative "../../../lib/plastic/commands/migration/list"
require_relative "../../../lib/plastic/commands/migration/purge"

class CLIMigrationStoreTest < Plastic::TestCase
  TEXT = "--store SLUG  the registered project whose store migrations the call works on"

  def help(command) = plastic("migration", command, "--help", table: Plastic::CLI::TABLE)

  def test_the_help_of_each_migration_command_says_store_names_the_project_whose_migrations_it_works_on
    results = %w[down list purge].map { |command| help(command) }

    assert_equal [[0, true]] * 3, results.map { |result| [result.code, result.out.squeeze(" ").include?(TEXT.squeeze(" "))] }
  end

  def test_the_help_of_a_backup_command_keeps_its_own_store_text
    result = plastic("backup", "list", "--help", table: Plastic::CLI::TABLE)

    assert_includes result.out.squeeze(" "), "--store SLUG the registered project whose backups the call works on"
  end
end
