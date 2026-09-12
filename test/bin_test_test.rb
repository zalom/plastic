# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# Intent 355 (n4), matrix 4.1-4.7. Drives bin/test as a subprocess against a
# tmpdir root holding tiny fixture test files, never the real suite: the real
# bin/test and failures_reporter.rb are copied into the fixture root so the
# script's own __dir__-relative paths resolve inside the tmpdir.
class BinTestTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  GREEN = <<~RUBY
    require "minitest/autorun"
    class GreenTest < Minitest::Test
      def test_it_passes
        assert true
      end
    end
  RUBY

  RED = <<~RUBY
    require "minitest/autorun"
    class RedTest < Minitest::Test
      def test_it_fails
        assert_equal 1, 2, "expected failure message"
      end
    end
  RUBY

  POISON = <<~RUBY
    raise "b_test.rb must never load under --only a_test.rb"
  RUBY

  def setup
    @dir = Dir.mktmpdir("bin-test-only")
    FileUtils.mkdir_p(File.join(@dir, "bin"))
    FileUtils.mkdir_p(File.join(@dir, "test", "lib"))
    FileUtils.cp(File.join(REPO, "bin", "test"), File.join(@dir, "bin", "test"))
    FileUtils.chmod(0o755, File.join(@dir, "bin", "test"))
    FileUtils.cp(File.join(REPO, "test", "lib", "failures_reporter.rb"),
                 File.join(@dir, "test", "lib", "failures_reporter.rb"))
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def write_test(name, body)
    File.write(File.join(@dir, "test", "#{name}.rb"), body)
  end

  def run_bin_test(*args)
    Open3.capture3("ruby", File.join(@dir, "bin", "test"), *args, chdir: @dir)
  end

  def test_only_loads_named_files
    write_test("a_test", GREEN)
    write_test("b_test", POISON)
    out, err, status = run_bin_test("--only", "test/a_test.rb")
    assert status.success?, "expected success, got: #{out}#{err}"
    assert_includes out, "1 runs, 1 assertions, 0 failures, 0 errors"
  end

  def test_only_missing_file_exit_2
    write_test("a_test", GREEN)
    _out, err, status = run_bin_test("--only", "test/no_such_test.rb")
    assert_equal 2, status.exitstatus
    assert_includes err, "no_such_test.rb"
  end

  def test_green_run_prints_summary_only
    write_test("a_test", GREEN)
    out, _err, status = run_bin_test("--only", "test/a_test.rb")
    assert status.success?
    lines = out.each_line.map(&:chomp).reject(&:empty?)
    assert_equal 1, lines.length, "expected exactly one line, got: #{out.inspect}"
    assert_match(/\A\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips\z/, lines.first)
  end

  def test_red_run_prints_failures_and_summary
    write_test("a_test", RED)
    out, _err, status = run_bin_test("--only", "test/a_test.rb")
    refute status.success?
    assert_includes out, "a_test.rb"
    assert_includes out, "expected failure message"
    assert_includes out, "1 runs, 1 assertions, 1 failures, 0 errors"
  end

  def test_full_run_summary_parses_as_before
    write_test("a_test", GREEN)
    out, _err, status = run_bin_test
    assert status.success?
    lines = out.each_line.map(&:chomp).reject(&:empty?)
    assert_equal 1, lines.length, "expected exactly one line, got: #{out.inspect}"
    assert_match(/\A\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips\z/, lines.first)
  end

  def test_list_still_prints_files
    write_test("a_test", GREEN)
    out, _err, status = run_bin_test("--list")
    assert status.success?
    assert_includes out, "test/a_test.rb"
  end
end
