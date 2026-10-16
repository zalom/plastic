# frozen_string_literal: true

require_relative "test_helper"

load File.expand_path("../bin/verify-change", __dir__) unless defined?(VerifyChange)

class VerifyChangeKernelMappingTest < Minitest::Test
  def test_a_kernel_file_maps_to_its_test_under_test_plastic
    assert_includes VerifyChange.test_candidates("lib/plastic/cli.rb"), "test/plastic/cli_test.rb"
  end

  def test_a_nested_kernel_file_maps_to_the_same_nesting_under_test
    assert_includes VerifyChange.test_candidates("lib/plastic/commands/intent/new.rb"), "test/plastic/commands/intent/new_test.rb"
  end
end
