# frozen_string_literal: true

require "fileutils"
require_relative "../../test_helper"

# With sync.lock on, every call that prints files, and every sync and repair,
# holds the store lock from its hand-edit check through its print. With
# sync.lock_wait at 0, a call that finds the lock held stops at once.
class RoutineStoreLockTest < Plastic::TestCase
  include LifecycleHelper

  BUSY = /: another call holds the store lock, and the wait of 0 seconds in sync\.lock_wait ran out$/

  def lock_path = File.join(@plastic_home, "locks", "global.lock")

  # Turns the lock on with no wait, so a held lock stops the call at once.
  def lock_on = %w[true 0].zip(%w[sync.lock sync.lock_wait]).each { |value, key| cli("config", "set", key, value) }

  def held_elsewhere
    FileUtils.mkdir_p(File.dirname(lock_path))
    file = File.open(lock_path, File::RDWR | File::CREAT)
    file.flock(File::LOCK_EX)
    file
  end

  def intent_count = store_database.row("SELECT COUNT(*) AS n FROM intents").fetch("n")

  def assert_busy(result)
    assert_equal 1, result.code
    assert_match BUSY, result.err
    assert_includes result.err, lock_path
  end

  def test_a_print_with_the_lock_held_stops_and_writes_no_row
    open_intent
    lock_on
    held_elsewhere
    before = intent_count
    result = cli("intent", "new", "Beta")

    assert_busy(result)
    assert_equal before, intent_count
  end

  def test_a_stopped_print_offers_the_same_call_again
    open_intent
    lock_on
    held_elsewhere

    assert_match(/^next: plastic intent new Beta\n/, cli("intent", "new", "Beta").out)
  end

  def test_a_sync_up_with_the_lock_held_stops
    open_intent
    lock_on
    held_elsewhere

    assert_busy(cli("store", "sync", "up"))
  end

  def test_a_sync_down_with_the_lock_held_stops
    open_intent
    lock_on
    held_elsewhere

    assert_busy(cli("store", "sync", "down"))
  end

  def test_a_repair_with_the_lock_held_stops
    open_intent
    lock_on
    held_elsewhere

    assert_busy(cli("intent", "repair", "1"))
  end

  def test_a_print_with_the_lock_free_finishes_and_frees_it
    open_intent
    lock_on
    result = cli("intent", "new", "Beta")

    assert_equal [0, true], [result.code, File.open(lock_path) { |file| file.flock(File::LOCK_EX | File::LOCK_NB) != false }]
  end

  def test_a_dry_run_takes_no_lock
    open_intent
    lock_on
    held_elsewhere

    assert_equal 0, cli("store", "sync", "up", "--dry-run").code
  end

  def test_a_call_that_prints_nothing_takes_no_lock
    open_intent
    lock_on
    held_elsewhere

    assert_equal 0, cli("intent", "show", "1").code
  end

  def test_with_the_lock_off_a_held_lock_file_stops_nothing
    open_intent
    held_elsewhere

    assert_equal 0, cli("intent", "new", "Beta").code
  end

  def test_with_the_lock_off_no_lock_folder_is_made
    open_intent
    cli("intent", "new", "Beta")
    cli("store", "sync", "up")

    refute_path_exists File.join(@plastic_home, "locks")
  end
end
