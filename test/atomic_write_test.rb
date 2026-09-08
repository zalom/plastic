# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/atomic_write"

# AtomicWrite (intent 334, n2, D19r): a sibling-temp-plus-rename write,
# following Lock#write's existing shape, with an injectable renamer so the
# interrupted-write case is testable without eval or a global.
class AtomicWriteTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("atomic-write")
    @path = File.join(@dir, "target.md")
    File.write(@path, "original content\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_original_survives_a_failed_rename
    assert_raises(RuntimeError) do
      AtomicWrite.write(@path, "new content\n", renamer: ->(_temp, _target) { raise "boom" })
    end
    assert_equal "original content\n", File.read(@path)
  end

  def test_temp_file_is_removed_on_failure
    before = Dir.entries(@dir).sort
    assert_raises(RuntimeError) do
      AtomicWrite.write(@path, "new content\n", renamer: ->(_temp, _target) { raise "boom" })
    end
    after = Dir.entries(@dir).sort
    assert_equal before, after, "a temp file was left behind after the failed rename"
  end

  def test_temp_file_is_a_sibling
    seen_temp = nil
    AtomicWrite.write(@path, "new content\n", renamer: lambda { |temp, target|
      seen_temp = temp
      File.rename(temp, target)
    })
    refute_nil seen_temp
    assert_equal @dir, File.dirname(seen_temp), "the temp file must live beside the target, not in a system tmpdir"
    assert_equal "new content\n", File.read(@path)
  end
end
