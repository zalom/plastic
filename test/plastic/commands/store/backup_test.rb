# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/store/backup"
require_relative "../../../../lib/plastic/commands/store/backup/restore"
require_relative "../../../../lib/plastic/commands/store/backup/list"

class BackupTest < Plastic::TestCase
  include BackupHomes

  DATABASES = %w[knowledge_graph work_graph].freeze

  def test_a_call_without_a_project_refuses_with_the_usage_line
    assert_refused_with_usage backup_call(fresh_home), "--project"
  end

  def test_an_unregistered_store_refuses_and_names_it
    home = fresh_home

    assert_refused_with_usage backup_call(home, "--project", "nowhere"), "nowhere"
    assert_empty folder_names(home, "nowhere")
  end

  def test_the_global_store_is_accepted
    home = fresh_home
    seed_store(home, "global")

    assert_equal 0, backup_call(home, "--project", "global").code
    assert_equal 1, folder_names(home, "global").size
  end

  def test_a_backup_holds_only_the_two_store_databases_named_with_the_timestamp
    home = fresh_home

    assert_equal 0, backup_call(home, "--project", "alpha").code
    folder = folder_names(home).first

    assert_match(/\A\d{14}\z/, folder)
    assert_equal DATABASES.map { |name| "#{name}-#{folder}.db" }, Dir.children(File.join(backups_dir(home), folder)).grep(/\.db\z/).sort
  end

  def test_a_backup_keeps_the_run_of_the_call_for_a_resume
    home = fresh_home
    backup_call(home, "--project", "alpha")

    assert_includes kept_run_tools(home), "store backup"
  end

  def test_databases_backs_up_only_that_database
    home = fresh_home
    backup_call(home, "--project", "alpha", "--databases", "work_graph")
    folder = folder_names(home).first

    assert_equal ["work_graph-#{folder}.db"], Dir.children(File.join(backups_dir(home), folder)).grep(/\.db\z/)
  end

  def test_an_unknown_name_refuses_and_lists_the_two
    home = fresh_home
    result = backup_call(home, "--project", "alpha", "--databases", "home")

    assert_refused_with_usage result, %w[knowledge_graph legacy references work_graph].join(", ")
    assert_empty folder_names(home)
  end

  def test_databases_takes_a_comma_list_and_counts_a_repeat_once
    home = fresh_home
    add_references(home)
    backup_call(home, "--project", "alpha", "--databases", "work_graph,references,work_graph")
    folder = folder_names(home).first

    assert_equal ["backup.log", "references-#{folder}.db", "status.yml", "work_graph-#{folder}.db"], Dir.children(File.join(backups_dir(home), folder)).sort
  end

  def test_a_backup_is_marked_done_with_the_goal_full
    home = fresh_home
    backup_call(home, "--project", "alpha")
    report = YAML.safe_load_file(File.join(backups_dir(home), folder_names(home).first, "status.yml"))

    assert_equal %w[done full], report.values_at("status", "goal")
  end

  def test_a_partial_backup_names_the_files_in_its_goal
    home = fresh_home
    backup_call(home, "--project", "alpha", "--databases", "work_graph")
    report = YAML.safe_load_file(File.join(backups_dir(home), folder_names(home).first, "status.yml"))

    assert_equal "partial:work_graph.db", report.fetch("goal")
  end

  def test_a_preview_writes_no_folder
    home = fresh_home
    result = backup_call(home, "--project", "alpha", "--dry-run")

    assert_equal 0, result.code
    assert_includes result.out, "preview"
    assert_empty folder_names(home)
  end

  def test_a_preview_names_the_databases_it_would_copy
    result = backup_call(fresh_home, "--project", "alpha", "--dry-run")

    DATABASES.each { |name| assert_includes result.out, name }
  end
end

class BackupLogTest < Plastic::TestCase
  include BackupHomes

  def log_in(home) = File.join(backups_dir(home), folder_names(home).first, "backup.log")

  def test_live_prints_the_log_lines_in_order
    home = fresh_home
    out = backup_call(home, "--project", "alpha", "--live").out
    lines = File.readlines(log_in(home), chomp: true)

    assert_equal lines, out.lines(chomp: true).first(lines.size)
  end

  def test_live_still_ends_with_the_backup_summary
    out = backup_call(fresh_home, "--project", "alpha", "--live").out

    assert_match(%r{^backup: alpha/\d{14}, 2 databases}, out)
  end

  def test_without_live_the_output_holds_no_log_line
    out = backup_call(fresh_home, "--project", "alpha").out

    refute_match(/result=/, out)
  end

  def test_a_backup_writes_the_log_in_its_folder_either_way
    home = fresh_home
    backup_call(home, "--project", "alpha")

    assert_path_exists log_in(home)
  end

  def test_restore_ignores_the_log
    home = fresh_home
    backup_call(home, "--project", "alpha")
    result = restore_call(home, "--project", "alpha", "--latest")

    assert_equal 0, result.code
    refute_includes result.out, "backup.log"
  end

  def test_list_ignores_the_log
    home = fresh_home
    backup_call(home, "--project", "alpha")
    out = list_call(home, "--project", "alpha").out

    refute_includes out, "backup.log"
    assert_match(/^1\s+\d{14}/, out)
  end

  def test_purge_removes_the_log_with_its_folder
    home = fresh_home
    backup_call(home, "--project", "alpha")
    purge_call(home, "--project", "alpha", "--all")

    assert_empty folder_names(home)
  end
end
