# frozen_string_literal: true

require "minitest/autorun"
# `load`, not `require_relative`: the script has no .rb suffix. main runs only
# when the script is the program, so this defines its helpers without running.
load File.expand_path("../scripts/end-intent", __dir__)

# The Git failures a real repository rarely shows. Each must refuse the close,
# never pass it (status 1 means "no", 128 means git itself failed).
class EndIntentUnmergedRefusalTest < Minitest::Test
  ON_MAIN = {"symbolic-ref" => "main\n"}.freeze

  class FakeRunner
    def initialize(statuses, stdout = {})
      @statuses = statuses
      @stdout = stdout
    end

    def run(*args)
      Worktree::ShellRunner::Result.new(@statuses.fetch(args[2]), @stdout.fetch(args[2], ""), "")
    end
  end

  def test_branch_lookup_failure_refuses
    msg = unmerged_branch(FakeRunner.new("show-ref" => 128), "/repo", "plastic/1--x")

    assert_equal "could not look up code branch plastic/1--x in /repo. " \
      "Check the repository, then run the close again", msg
  end

  def test_missing_branch_is_left_to_the_worktree_guard
    assert_nil unmerged_branch(FakeRunner.new("show-ref" => 1), "/repo", "plastic/1--x")
  end

  def test_found_branch_is_checked_for_ancestry
    runner = FakeRunner.new({"show-ref" => 0, "symbolic-ref" => 0, "merge-base" => 1}, ON_MAIN)

    assert_equal "code branch plastic/1--x is not merged into the current branch of /repo. " \
      "Merge it there first (git -C /repo merge plastic/1--x), then run the close again",
      unmerged_branch(runner, "/repo", "plastic/1--x")
  end

  def test_ancestry_check_failure_refuses
    msg = ancestry_refusal(FakeRunner.new({"symbolic-ref" => 0, "merge-base" => 128}, ON_MAIN),
      "/repo", "abc", "abc", "code branch b", "b")

    assert_equal "code branch b could not be checked against the current branch of /repo. " \
      "Merge it there first (git -C /repo merge abc), then run the close again", msg
  end

  def test_merged_ancestry_passes
    runner = FakeRunner.new({"symbolic-ref" => 0, "merge-base" => 0}, ON_MAIN)

    assert_nil ancestry_refusal(runner, "/repo", "abc", "abc", "x", "b")
  end

  def test_detached_checkout_is_no_merge_target
    msg = target_refusal(FakeRunner.new("symbolic-ref" => 1), "/repo", "b")

    assert_equal "the repo checkout /repo is not on a branch, so no branch holds the merged code. " \
      "Check out the branch you release from, merge b into it, then run the close again", msg
  end

  def test_the_code_branch_itself_is_no_merge_target
    msg = target_refusal(FakeRunner.new({"symbolic-ref" => 0}, {"symbolic-ref" => "b\n"}), "/repo", "b")

    assert_equal "the repo checkout /repo is on the code branch b itself, so the code is not merged anywhere. " \
      "Check out the branch you release from, merge b into it, then run the close again", msg
  end

  def test_an_attached_other_branch_is_a_merge_target
    assert_nil target_refusal(FakeRunner.new({"symbolic-ref" => 0}, ON_MAIN), "/repo", "b")
  end

  def test_no_merge_target_refuses_before_the_ancestry_check
    msg = ancestry_refusal(FakeRunner.new("symbolic-ref" => 1), "/repo", "abc", "abc", "x", "b")

    assert_includes msg, "is not on a branch"
  end

  def test_plain_directory_is_not_a_real_worktree
    Dir.mktmpdir do |dir|
      refute real_worktree?(FakeRunner.new({"rev-parse" => 0}, {"rev-parse" => "/elsewhere\n"}), dir)
      refute real_worktree?(FakeRunner.new("rev-parse" => 128), dir)
      assert real_worktree?(FakeRunner.new({"rev-parse" => 0}, {"rev-parse" => "#{dir}\n"}), dir)
    end
  end

  def test_missing_directory_is_not_a_real_worktree
    refute real_worktree?(FakeRunner.new({}), "/no/such/worktree")
  end
end
