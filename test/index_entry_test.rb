require "minitest/autorun"
require "tmpdir"
require "fileutils"

require File.expand_path("../../scripts/lib/index_entry.rb", __FILE__)

class IndexEntryTest < Minitest::Test
  def setup
    @home = File.join(Dir.mktmpdir("plastic-index-entry-test"))
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def store
    File.join(@home, "store")
  end

  def write_index(body)
    FileUtils.mkdir_p(@home)
    File.write(File.join(@home, "INDEX.md"), body)
  end

  def test_match_accepts_em_dash_and_hyphen
    em_dash = IndexEntry.match("- [96 #{IndexEntry::EM_DASH} demo](store/96--demo/96--demo.md)")
    hyphen = IndexEntry.match("- [96 - demo](store/96--demo/96--demo.md)")
    refute_nil em_dash
    refute_nil hyphen
    assert_equal "96", em_dash[1]
    assert_equal "96", hyphen[1]
    assert_nil IndexEntry.match("- plain bullet with no entry shape")
  end

  def test_active_only_inside_the_active_section
    FileUtils.mkdir_p(store)
    write_index(<<~MD)
      ## Active
      - [96 #{IndexEntry::EM_DASH} demo](store/96--demo/96--demo.md)

      ## Future
      - [97 #{IndexEntry::EM_DASH} later](store/97--later/97--later.md)
    MD

    assert IndexEntry.active?("96", store: store)
    refute IndexEntry.active?("97", store: store)
  end

  def test_active_is_false_for_a_missing_index
    refute IndexEntry.active?("96", store: File.join(@home, "no-such-store"))
  end
end
