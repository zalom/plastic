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
    assert File.exist?(path), "bin/test must exist"
    assert File.executable?(path), "bin/test must be executable"
  end

  def test_bin_test_discovers_every_test_file
    listed, status = Open3.capture2("ruby", "bin/test", "--list", chdir: ROOT)
    assert status.success?, "bin/test --list failed: #{listed}"

    discovered = listed.split("\n").sort
    expected = Dir.glob("test/**/*_test.rb", base: ROOT).sort

    assert_operator expected.length, :>, 1, "sanity: suite has more than one test file"
    assert_equal expected, discovered,
      "bin/test must discover every test file, not just the first"
  end
end
