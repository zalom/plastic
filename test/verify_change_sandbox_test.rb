# encoding: UTF-8
# frozen_string_literal: true

require_relative "test_helper"
require "etc"
require "tmpdir"

load File.expand_path("../bin/verify-change", __dir__)

# Every step of the change gate runs under a throwaway home, so a test the gate
# starts cannot reach the machine's own ~/.plastic or ~/.claude.
class VerifyChangeSandboxTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REAL_HOME = Etc.getpwuid(Process.uid).dir
  CHANGED_SOURCE = "scripts/lib/plastic/hooks/entries.rb"
  SANDBOX = { "HOME" => "/nowhere/home", "PLASTIC_TMP" => "/nowhere/tmp" }.freeze

  def planned_steps(sandbox)
    VerifyChange.new([], root: ROOT, sandbox: sandbox)
      .plan(changed: [CHANGED_SOURCE],
        extra_tests: ["test/real_home_guard_test.rb"], base: "HEAD", rails: false)
  end

  def test_the_planned_change_names_a_source_file_that_exists
    assert_path_exists File.join(ROOT, CHANGED_SOURCE)
    assert_equal [CHANGED_SOURCE], planned_steps({ "PLASTIC_TMP" => "/nowhere/tmp" }).sources
  end

  def gate_steps
    plan = planned_steps(SANDBOX)
    plan.steps + [plan.lint_decision.step].compact
  end

  def test_the_plan_holds_the_source_steps_beside_the_tests_step
    assert_operator gate_steps.size, :>, 1
  end

  def test_every_gate_step_runs_under_the_sandbox_home
    gate_steps.each do |step|
      assert_equal SANDBOX, step.env.slice("HOME", "PLASTIC_TMP"), "#{step.title} runs under the ambient home or tmp dir"
    end
  end

  def test_the_step_environment_keeps_its_own_variables
    plan = planned_steps(SANDBOX)
    tests = plan.steps.find { |step| step.title == VerifyChange::TESTS_STEP }

    assert_equal "1", tests.env["COVERAGE"]
  end

  def test_the_default_sandbox_is_a_fresh_directory_outside_the_real_home
    subject = VerifyChange.new([], root: ROOT)
    home = subject.sandbox["HOME"]

    refute home.start_with?(REAL_HOME), "the sandbox home sits inside #{REAL_HOME}"
    assert_empty Dir.children(home)
  ensure
    subject&.discard_sandbox
  end

  def test_the_sandbox_is_discarded_after_the_run
    subject = VerifyChange.new([], root: ROOT)
    home = subject.sandbox["HOME"]
    subject.discard_sandbox

    refute_path_exists home
  end
end
