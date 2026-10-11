# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../scripts/lib/plastic/hooks/ownership"

class OwnershipTest < Minitest::Test
  COMMAND = "/opt/plastic/bin/plastic"

  def ownership = Plastic::Hooks::Ownership.new([COMMAND, nil])

  def test_the_bare_command_is_owned
    assert ownership.own?(COMMAND)
  end

  def test_a_command_that_quotes_the_launcher_is_owned
    assert ownership.own?(%(env -u RUBYOPT "#{COMMAND}" hook start || true))
  end

  def test_a_command_that_names_an_earlier_launcher_file_is_owned
    assert ownership.own?("ruby '/home/me/.claude/hooks/plastic-session-start.rb'")
  end

  def test_the_codex_dispatcher_of_an_earlier_install_is_owned
    assert ownership.own?("/home/me/.codex/hooks/codex-hook")
  end

  def test_a_user_command_that_only_contains_a_launcher_name_is_not_owned
    refute ownership.own?("/home/me/bin/plastic-writing-style")
  end

  def test_an_unquoted_mention_of_the_launcher_inside_another_command_is_not_owned
    refute ownership.own?("echo #{COMMAND}-backup")
  end
end
