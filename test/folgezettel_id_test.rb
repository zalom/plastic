require "minitest/autorun"
require "tmpdir"
require "fileutils"

class FolgezettelIdTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/folgezettel-id", __FILE__)

  def setup
    @dir = Dir.mktmpdir("folgezettel-test")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def run_script(*args)
    `ruby #{SCRIPT} #{args.join(" ")}`.strip
  end

  def mkdir(id, slug = "test-intent")
    FileUtils.mkdir_p("#{@dir}/#{id}--#{slug}")
  end

  def test_first_root
    assert_equal "1", run_script(@dir)
  end

  def test_next_root
    mkdir("1")
    mkdir("2")
    assert_equal "3", run_script(@dir)
  end

  def test_first_child_of_number
    mkdir("1")
    assert_equal "1a", run_script(@dir, "1")
  end

  def test_second_child_of_number
    mkdir("1")
    mkdir("1a")
    assert_equal "1b", run_script(@dir, "1")
  end

  def test_child_of_letter
    mkdir("1a")
    assert_equal "1a1", run_script(@dir, "1a")
  end

  def test_second_child_of_letter
    mkdir("1a")
    mkdir("1a1")
    assert_equal "1a2", run_script(@dir, "1a")
  end

  def test_deep_nesting
    mkdir("1a1b1a")
    mkdir("1a1b1a1")
    mkdir("1a1b1a2")
    assert_equal "1a1b1a3", run_script(@dir, "1a1b1a")
  end
end
