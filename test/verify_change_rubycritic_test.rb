# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

load File.expand_path("../bin/verify-change", __dir__) unless defined?(VerifyChange)

# RubyCritic scores only code written after the 2026-09-30 ruling. A file that
# .rubocop_todo.yml or .reek.yml lists is older code whose offenses and smells
# stay hidden, so the gate leaves it out of the score and says so.
class VerifyChangeRubycriticTest < Minitest::Test
  OLD = "scripts/lib/old_installer.rb"
  NEW = "scripts/lib/plastic/new_routine.rb"

  def setup
    @root = Dir.mktmpdir("verify-change-rubycritic")
    write("Gemfile.lock", "GEM\n  specs:\n\nDEPENDENCIES\n  rubycritic (~> 4.12)\n\n")
    write(".rubocop_todo.yml", "Metrics/AbcSize:\n  Exclude:\n    - '#{OLD}'\n")
    write(".reek.yml", "# #{NEW} has no entry\n---\nexclude_paths:\n  - test\n")
    [OLD, NEW, "test/old_installer_test.rb", "test/plastic/new_routine_test.rb"].each { |path| write(path, "") }
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write(path, body)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  def critic_step(changed)
    VerifyChange.new([], root: @root, err: @err, sandbox: { "HOME" => "/nowhere", "PLASTIC_TMP" => "/nowhere" })
      .plan(changed:, extra_tests: [], base: "HEAD", rails: false)
      .steps.find { |step| step.title == "RubyCritic score" }
  end

  def test_rubycritic_scores_only_the_files_no_todo_lists
    command = critic_step([OLD, NEW]).command

    assert_includes command, NEW
    refute_includes command, OLD
    assert_includes @err.string, "Not checked by RubyCritic"
    assert_includes @err.string, OLD
  end

  def test_rubycritic_is_skipped_when_every_changed_file_is_listed
    assert_nil critic_step([OLD])
    assert_includes @err.string, "Not checked by RubyCritic"
  end

  def test_a_file_named_only_in_a_comment_is_not_listed
    assert_includes critic_step([NEW]).command, NEW
    assert_empty @err.string
  end
end
