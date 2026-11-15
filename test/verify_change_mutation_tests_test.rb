# frozen_string_literal: true

require_relative "test_helper"

load File.expand_path("../bin/verify-change", __dir__) unless defined?(VerifyChange)

# The mutation step gets unit and integration tests only: kernel tests that start no child process.
class VerifyChangeMutationTestsTest < Minitest::Test
  TEXTS = {
    "test/plastic/cli_test.rb" => "class CLITest < Plastic::TestCase; end",
    "test/plastic/graph/prints_test.rb" => "class PrintsTest < Plastic::TestCase; end",
    "test/plastic/hooks/broken_store_test.rb" => "KernelCommand.new(home).command!(\"hook\", \"start\")",
    "test/plastic/commands/uninstall_test.rb" => "ChildProcess.capture(env, \"ruby\", \"-e\", \"1\")",
    "test/no_version_control_guard_test.rb" => "class NoVersionControlGuardTest < Minitest::Test; end",
    "test/install_sh_dependency_test.rb" => "class InstallShDependencyTest < Minitest::Test; include InstallShHelper; end",
    "test/varar/sync_second_home.steps.rb" => "step(\"a second home\") {}"
  }.freeze

  def kept(paths) = VerifyChange.mutation_tests(paths, TEXTS.method(:fetch))

  def test_a_kernel_test_that_starts_no_process_goes_to_the_mutation_step
    assert_equal %w[test/plastic/cli_test.rb test/plastic/graph/prints_test.rb], kept(TEXTS.keys.first(2))
  end

  def test_a_kernel_test_that_starts_a_child_process_stays_out
    assert_empty kept(%w[test/plastic/hooks/broken_store_test.rb test/plastic/commands/uninstall_test.rb])
  end

  def test_a_guard_test_an_installer_test_and_an_acceptance_step_stay_out
    assert_empty kept(%w[test/no_version_control_guard_test.rb test/install_sh_dependency_test.rb test/varar/sync_second_home.steps.rb])
  end
end
