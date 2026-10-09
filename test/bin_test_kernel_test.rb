# frozen_string_literal: true

require "minitest/autorun"
require_relative "lib/bin_test_support"

class BinTestKernelTest < Minitest::Test
  include BinTestSupport

  # The kernel under scripts/lib/plastic/ defines the same
  # constants as the live command line, so its tests run in their own process.
  LIVE = <<~RUBY
    require "minitest/autorun"
    LIVE_LOADED = true
    class LiveTest < Minitest::Test
      def test_it_passes
        assert true
      end
    end
  RUBY

  KERNEL = <<~RUBY
    require "minitest/autorun"
    class KernelTest < Minitest::Test
      def test_the_live_files_are_not_loaded
        refute defined?(LIVE_LOADED), "a live test file loaded in the kernel process"
      end
    end
  RUBY

  def write_kernel_test(name, body)
    FileUtils.mkdir_p(File.join(@dir, "test", "plastic"))
    File.write(File.join(@dir, "test", "plastic", "#{name}.rb"), body)
  end

  def test_full_run_runs_the_kernel_tests_in_their_own_process
    write_test("a_test", LIVE)
    write_kernel_test("k_test", KERNEL)
    out, err, status = run_bin_test

    assert_predicate status, :success?, "expected success, got: #{out}#{err}"
    assert_equal 2, out.scan("1 runs, 1 assertions, 0 failures, 0 errors").size
  end

  def test_full_run_fails_when_only_the_kernel_tests_fail
    write_test("a_test", LIVE)
    write_kernel_test("k_test", RED)
    out, _err, status = run_bin_test

    refute_predicate status, :success?
    assert_includes out, "expected failure message"
  end

  def test_full_run_with_only_kernel_tests_runs_them
    write_kernel_test("k_test", KERNEL)
    out, err, status = run_bin_test

    assert_predicate status, :success?, "expected success, got: #{out}#{err}"
    assert_includes out, "1 runs, 1 assertions, 0 failures, 0 errors"
  end
end
