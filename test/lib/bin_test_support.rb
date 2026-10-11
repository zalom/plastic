# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../support/child_process"

# A tmpdir root that holds copies of the real bin/test and failures_reporter.rb,
# so the script's own __dir__-relative paths resolve inside it.
module BinTestSupport
  REPO = File.expand_path("../..", __dir__)

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
    ChildProcess.capture3("ruby", File.join(@dir, "bin", "test"), *args, chdir: @dir)
  end
end
