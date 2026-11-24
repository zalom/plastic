# frozen_string_literal: true

require "fileutils"
require_relative "../../test_helper"

# Every call that prints files, and every sync and repair, holds the store lock
# from its hand-edit check through its print. With the wait of Wiring at 0, a
# call that finds the lock held stops at once.
class RoutineStoreLockTest < Plastic::TestCase
  include LifecycleHelper

  BUSY = /: another call holds the store lock, and the wait of 0 seconds ran out$/

  def lock_path = File.join(@plastic_home, "locks", "global.lock")

  # No wait, so a held lock stops the call at once.
  def setup
    super
    Plastic::Wiring.lock_wait = 0
  end

  def teardown
    @held&.close
    Plastic::Wiring.lock_wait = nil
    super
  end

  # Kept in @held until the teardown, so the garbage collector cannot close the file and free the lock mid-test.
  def held_elsewhere
    FileUtils.mkdir_p(File.dirname(lock_path))
    @held = File.open(lock_path, File::RDWR | File::CREAT)
    @held.flock(File::LOCK_EX)
  end

  def intent_count = store_database.row("SELECT COUNT(*) AS n FROM intents").fetch("n")

  def assert_busy(result)
    assert_equal 1, result.code
    assert_match BUSY, result.err
    assert_includes result.err, lock_path
  end

  def test_a_print_with_the_lock_held_stops_and_writes_no_row
    open_intent
    held_elsewhere
    before = intent_count
    result = cli("intent", "new", "Beta")

    assert_busy(result)
    assert_equal before, intent_count
  end

  def test_a_stopped_print_offers_the_same_call_again
    open_intent
    held_elsewhere

    assert_match(/^next: plastic intent new Beta\n/, cli("intent", "new", "Beta").out)
  end

  def test_a_sync_up_with_the_lock_held_stops
    open_intent
    held_elsewhere

    assert_busy(cli("store", "sync", "up"))
  end

  def test_a_sync_down_with_the_lock_held_stops
    open_intent
    held_elsewhere

    assert_busy(cli("store", "sync", "down"))
  end

  def test_a_repair_with_the_lock_held_stops
    open_intent
    held_elsewhere

    assert_busy(cli("intent", "repair", "1"))
  end

  def test_a_print_with_the_lock_free_finishes_and_frees_it
    open_intent
    result = cli("intent", "new", "Beta")

    assert_equal [0, true], [result.code, File.open(lock_path) { |file| file.flock(File::LOCK_EX | File::LOCK_NB) != false }]
  end

  def test_a_dry_run_takes_no_lock
    open_intent
    held_elsewhere

    assert_equal 0, cli("store", "sync", "up", "--dry-run").code
  end

  def test_a_call_that_prints_nothing_takes_no_lock
    open_intent
    held_elsewhere

    assert_equal 0, cli("intent", "show", "1").code
  end
end
