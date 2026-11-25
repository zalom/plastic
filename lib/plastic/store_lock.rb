# frozen_string_literal: true

require "fileutils"
require_relative "errors"

module Plastic
  # The lock that the printing calls and the syncs of one store share: an
  # exclusive file lock on ~/.plastic/locks/SLUG.lock. A second holder pauses
  # and tries again until its wait runs out. A thread that holds the lock takes
  # it again at once. The operating system frees it when its holder ends.
  class StoreLock
    PAUSE = 0.05
    WAIT = 60
    LINE = "%s: another call holds the store lock, and the wait of %s seconds ran out"
    HELD = :plastic_store_locks

    # Another call held the lock past the wait.
    class Busy < Failed; end

    def self.path(home, slug) = File.join(home, "locks", "#{slug}.lock")

    # The lock files this thread holds.
    def self.held = Thread.current.then { |thread| thread.thread_variable_get(HELD) || thread.thread_variable_set(HELD, []) }

    def initialize(path, wait: WAIT, pause: ->(seconds) { sleep(seconds) })
      @path = path
      @wait = wait
      @pause = pause
    end

    # Runs the block with the lock held, and gives its value.
    def hold(&)
      return yield if StoreLock.held.include?(@path)

      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, File::RDWR | File::CREAT) do |file|
        wait_for(file)
        holding(&)
      end
    end

    private

    def wait_for(file)
      tries = (@wait / PAUSE).round
      until file.flock(File::LOCK_EX | File::LOCK_NB)
        raise Busy, format(LINE, @path, @wait) if tries.zero?

        tries -= 1
        @pause.call(PAUSE)
      end
    end

    def holding
      held = StoreLock.held
      held << @path
      yield
    ensure
      held.delete(@path)
    end
  end
end
