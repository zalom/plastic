# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# Guards the release-gate runner (bin/test) against the intent-30 bug:
# `ruby -Itest test/*_test.rb` runs only the FIRST glob-expanded file, so the
# gate exercised one file and reported green over real failures. bin/test must
# discover every test file. We check discovery via `--list` — no suite run.
class ReleaseVerifyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_bin_test_exists_and_is_executable
    path = File.join(ROOT, "bin", "test")

    assert_path_exists path, "bin/test must exist"
    assert File.executable?(path), "bin/test must be executable"
  end

  SYSTEM_RUNNER = "test/varar_test.rb"

  def listing(*argv)
    listed, status = Open3.capture2("ruby", "bin/test", *argv, "--list", chdir: ROOT)

    assert_predicate status, :success?, "bin/test #{argv.join(" ")} --list failed: #{listed}"
    listed.split("\n").sort
  end

  def test_bin_test_discovers_every_unit_test_file
    expected = Dir.glob("test/**/*_test.rb", base: ROOT).sort - [SYSTEM_RUNNER]

    assert_operator expected.length, :>, 1, "sanity: suite has more than one test file"
    assert_equal expected, listing, "bin/test must discover every unit test file, not just the first"
  end

  def test_bin_test_system_lists_the_varar_runner
    assert_equal [SYSTEM_RUNNER], listing("--system")
  end
end
