# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeBackupReplacementTest < Plastic::TestCase
  Replacement = Plastic::Graph::Knowledge::Backup::Replacement

  def setup
    super
    @dir = Dir.mktmpdir
    @target = File.join(@dir, "work_graph.db")
    @source = File.join(@dir, "backup.db")
    File.write(@source, "from the backup")
  end

  def test_applying_puts_the_backup_in_place_and_keeps_the_old_file_aside
    File.write(@target, "current")
    Replacement.new(@source, @target).apply

    assert_equal ["from the backup", "current"], [File.read(@target), File.read("#{@target}.old")]
  end

  def test_committing_removes_the_old_file
    File.write(@target, "current")
    Replacement.new(@source, @target).apply.commit

    assert_equal ["from the backup", false], [File.read(@target), File.exist?("#{@target}.old")]
  end

  def test_undoing_after_an_apply_puts_the_old_file_back
    File.write(@target, "current")
    replacement = Replacement.new(@source, @target).apply
    replacement.undo

    assert_equal "current", File.read(@target)
  end

  def test_undoing_after_an_apply_with_no_old_file_removes_the_new_one
    replacement = Replacement.new(@source, @target).apply
    replacement.undo

    refute_path_exists @target
  end

  def test_a_missing_source_fails_and_leaves_the_current_file_alone
    File.write(@target, "current")

    assert_raises(Errno::ENOENT) { Replacement.new(File.join(@dir, "absent.db"), @target).apply }
    assert_equal "current", File.read(@target)
  end

  def test_applying_clears_the_sidecar_files_of_the_target
    File.write(@target, "current")
    File.write("#{@target}-wal", "log")
    Replacement.new(@source, @target).apply

    refute_path_exists "#{@target}-wal"
  end

  def test_apply_all_undoes_the_applied_files_when_a_later_one_fails
    File.write(@target, "current")
    second = Replacement.new(File.join(@dir, "absent.db"), File.join(@dir, "knowledge_graph.db"))

    assert_raises(Errno::ENOENT) { Replacement.apply_all([Replacement.new(@source, @target), second]) }
    assert_equal "current", File.read(@target)
  end

  def test_apply_all_commits_every_file_when_all_succeed
    File.write(@target, "current")
    Replacement.apply_all([Replacement.new(@source, @target)])

    assert_equal ["from the backup", false], [File.read(@target), File.exist?("#{@target}.old")]
  end
end
