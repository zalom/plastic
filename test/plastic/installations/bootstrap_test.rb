# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "install_fixture"
require_relative "../../varar/support/kernel_command"
require "plastic/installations/bootstrap"

class BootstrapTest < Plastic::TestCase
  include InstallFixture

  def bootstrap = capture_io { Plastic::Installations::Bootstrap.new(plastic).call }

  def global(*parts) = File.join(Plastic::StoreLayout.global_store(plastic), *parts)

  def command(*argv) = KernelCommand.new(fresh).run(*argv)

  def test_a_first_install_says_what_it_does
    out, = bootstrap

    assert_equal ["  First install - bootstrapping store...\n", "  Store bootstrapped\n"], out.lines
  end

  def test_a_first_install_writes_the_config_the_projects_file_and_the_agent_instructions
    bootstrap

    assert_equal ["version: 3\n", "---\nprojects: {}\n", true],
      [File.read(File.join(plastic, "config.yml")), File.read(File.join(plastic, "projects.yml")),
        File.read(File.join(plastic, "AGENTS.md")).start_with?("# Plastic: Agent Instructions\n")]
  end

  def test_a_first_install_keeps_a_config_that_is_already_there
    FileUtils.mkdir_p(plastic)
    File.write(File.join(plastic, "config.yml"), "version: 3\nscreens: false\n")
    bootstrap

    assert_equal "version: 3\nscreens: false\n", File.read(File.join(plastic, "config.yml"))
  end

  def test_a_first_install_writes_no_legacy_index_into_the_global_store
    bootstrap

    refute_path_exists global("INDEX.md")
  end

  def test_a_first_install_creates_the_three_store_databases
    bootstrap

    assert_equal %w[knowledge_graph.db references.db work_graph.db], Dir.children(File.dirname(global)).grep(/\.db\z/).sort
  end

  def test_a_first_install_leaves_the_store_ready_for_intent_new
    bootstrap
    call = command("intent", "new", "First")

    assert_equal [0, true], [call.code, Dir.exist?(global("1--first"))]
  end

  def test_a_first_install_leaves_the_store_readable_by_search
    bootstrap
    call = command("search", "nothing-matches-this")

    assert_equal [0, ""], [call.code, call.err]
  end

  def test_a_first_install_over_a_legacy_home_creates_no_new_global_store
    FileUtils.mkdir_p(plastic)
    File.write(File.join(plastic, "INDEX.md"), "# Index\n")
    bootstrap

    refute_path_exists File.join(File.dirname(global), "work_graph.db")
  end

  def test_an_install_over_a_store_that_has_its_index_leaves_it_byte_for_byte
    FileUtils.mkdir_p(global)
    File.binwrite(global("INDEX.md"), "# Index\n\n## Active\n\n- 1 first\n")
    bootstrap

    assert_equal "# Index\n\n## Active\n\n- 1 first\n", File.binread(global("INDEX.md"))
  end
end
