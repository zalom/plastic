# frozen_string_literal: true

require "fileutils"
require_relative "../test_helper"
require_relative "../../lib/plastic/store_lock"

# The lock one store's printing calls and syncs share: a file lock that a
# second holder waits on, up to its wait, and that its own holder takes again.
class StoreLockTest < Plastic::TestCase
  def lock_path = File.join(@plastic_home, "locks", "global.lock")

  def no_pause = ->(_seconds) {}

  def lock(wait: 60, pause: no_pause) = Plastic::StoreLock.new(lock_path, wait:, pause:)

  # The lock as another call holds it: its own open file, locked.
  def held_elsewhere
    FileUtils.mkdir_p(File.dirname(lock_path))
    file = File.open(lock_path, File::RDWR | File::CREAT)
    file.flock(File::LOCK_EX)
    file
  end

  def free? = File.open(lock_path) { |file| file.flock(File::LOCK_EX | File::LOCK_NB) != false }

  def test_a_free_lock_runs_the_block_and_gives_its_value
    assert_equal :ran, lock.hold { :ran }
  end

  def test_the_lock_makes_its_folder_and_file
    lock.hold { nil }

    assert_path_exists lock_path
  end

  def test_a_second_holder_waits_until_the_first_lets_go
    other = held_elsewhere
    pauses = []
    value = lock(pause: lambda { |seconds|
      pauses << seconds
      other.flock(File::LOCK_UN)
    }).hold { :ran }

    assert_equal [[Plastic::StoreLock::PAUSE], :ran], [pauses, value]
  end

  def test_a_holder_past_its_wait_fails_and_names_the_lock_file
    held_elsewhere
    ran = false
    error = assert_raises(Plastic::StoreLock::Busy) { lock(wait: 1).hold { ran = true } }

    assert_equal ["#{lock_path}: another call holds the store lock, and the wait of 1 seconds ran out", false], [error.message, ran]
  end

  def test_a_wait_of_one_second_pauses_twenty_times_before_it_fails
    held_elsewhere
    pauses = []
    assert_raises(Plastic::StoreLock::Busy) { lock(wait: 1, pause: ->(seconds) { pauses << seconds }).hold { nil } }

    assert_equal 20, pauses.size
  end

  def test_a_wait_of_zero_fails_at_once
    held_elsewhere
    pauses = []
    assert_raises(Plastic::StoreLock::Busy) { lock(wait: 0, pause: ->(seconds) { pauses << seconds }).hold { nil } }

    assert_empty pauses
  end

  def test_a_holder_takes_the_lock_again_inside_its_own_hold
    value = lock(wait: 0).hold { lock(wait: 0).hold { :inner } }

    assert_equal :inner, value
  end

  def test_the_lock_is_free_after_the_hold
    lock.hold { nil }

    assert_predicate self, :free?
  end

  def test_the_lock_is_free_after_a_block_that_raises
    assert_raises(RuntimeError) { lock.hold { raise "broke" } }

    assert_predicate self, :free?
  end

  def test_the_lock_is_free_after_a_nested_hold_ends_and_the_outer_one_ends
    lock.hold { lock.hold { nil } }

    assert_predicate self, :free?
  end
end
