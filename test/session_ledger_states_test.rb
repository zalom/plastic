# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/session_ledger"

# Intent 301, ledger additions: the moved, dropped, and promoted states, the
# any-session addressing mode of set_state, and flip_all. In-process only, so
# no PLASTIC_TMP or session-id isolation is needed.
class SessionLedgerStatesTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("ledger-states")
    @path = File.join(@store, "checklist.md")
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def seed(*lines)
    File.write(@path, lines.join)
  end

  def line(state, session, summary)
    SessionLedger.checklist_line(state, session, "proj", summary)
  end

  # --- states ---------------------------------------------------------------

  def test_states_has_six_one_byte_markers
    expected = { pending: "~", open: " ", done: "x", moved: ">", dropped: "-", promoted: "^" }
    assert_equal expected, SessionLedger::STATES
    SessionLedger::STATES.each_value { |m| assert_equal 1, m.bytesize }
  end

  def test_parse_reads_the_three_new_states
    %i[moved dropped promoted].each do |state|
      parsed = SessionLedger.parse_checklist_line(line(state, "abc", "x"))
      assert_equal state, parsed[:state]
    end
  end

  # --- set_state, any session ------------------------------------------------

  def test_set_state_with_session_nil_flips_the_newest_matching_line_of_any_session
    seed(line(:open, "aaa", "first"), line(:open, "bbb", "second"), line(:open, "ccc", "third"))
    summary = SessionLedger.set_state(@path, from: :open, to: :promoted, session: nil)
    assert_equal "third", summary
    lines = File.readlines(@path)
    assert_equal "- [ ]", lines[0][0, 5]
    assert_equal "- [ ]", lines[1][0, 5]
    assert_equal "- [^]", lines[2][0, 5]
  end

  def test_set_state_with_session_nil_and_match_flips_exactly_one
    seed(line(:open, "aaa", "fix typo"), line(:open, "bbb", "fix typo again"), line(:open, "ccc", "other"))
    SessionLedger.set_state(@path, from: :open, to: :promoted, session: nil, match: "typo")
    assert_equal 1, File.read(@path).scan("- [^]").size
    assert_equal "- [^]", File.readlines(@path)[1][0, 5]
  end

  # --- flip_all ---------------------------------------------------------------

  def test_flip_all_flips_only_the_session_lines_in_the_from_state_and_returns_the_count
    seed(line(:pending, "aaa", "one"), line(:pending, "bbb", "two"), line(:open, "aaa", "three"),
         line(:pending, "aaa", "four"))
    count = SessionLedger.flip_all(@path, from: :pending, to: :dropped, session: "aaa")
    assert_equal 2, count
    lines = File.readlines(@path)
    assert_equal "- [-]", lines[0][0, 5]
    assert_equal "- [~]", lines[1][0, 5]
    assert_equal "- [ ]", lines[2][0, 5]
    assert_equal "- [-]", lines[3][0, 5]
  end

  def test_flip_all_with_session_nil_and_match_narrows_to_matching_lines
    seed(line(:open, "aaa", "carry me"), line(:open, "bbb", "keep"), line(:open, "ccc", "carry me too"))
    count = SessionLedger.flip_all(@path, from: :open, to: :moved, session: nil, match: "carry")
    assert_equal 2, count
    assert_equal ["- [>]", "- [ ]", "- [>]"], File.readlines(@path).map { |l| l[0, 5] }
  end

  def test_flip_all_changes_exactly_one_byte_per_flipped_line
    seed(line(:pending, "aaa", "one"), line(:open, "aaa", "two"), line(:pending, "aaa", "three"))
    before = File.binread(@path)
    SessionLedger.flip_all(@path, from: :pending, to: :dropped, session: "aaa")
    after = File.binread(@path)
    assert_equal before.bytesize, after.bytesize
    diff = before.bytes.zip(after.bytes).count { |a, b| a != b }
    assert_equal 2, diff
  end

  def test_flip_all_returns_zero_and_writes_nothing_when_nothing_matches
    seed(line(:open, "aaa", "one"))
    before = File.binread(@path)
    assert_equal 0, SessionLedger.flip_all(@path, from: :pending, to: :dropped, session: "aaa")
    assert_equal before, File.binread(@path)
  end

  def test_flip_all_returns_zero_when_the_file_is_missing
    assert_equal 0, SessionLedger.flip_all(@path, from: :pending, to: :dropped, session: "aaa")
    refute File.exist?(@path)
  end

  def test_flip_all_raises_rather_than_writing_unlocked
    seed(line(:pending, "aaa", "one"))
    refusing = ->(_handle, _mode) { raise Errno::ENOLCK }
    assert_raises(SessionLedger::LockUnavailableError) do
      SessionLedger.flip_all(@path, from: :pending, to: :dropped, session: "aaa", flock: refusing)
    end
    assert_equal "- [~]", File.read(@path)[0, 5]
  end
end
