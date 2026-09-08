# encoding: UTF-8
# frozen_string_literal: true

# GuardedAppend - the shared fail-closed write guard behind NodeLedger's transition
# lines and RoadmapSavepoint's roadmap ledger (intent 335, spec "Approach").
#
# One module function, #call: opens `path` RDWR|APPEND|CREAT, takes a non-blocking
# exclusive lock with a bounded number of retries, and under that ONE hold reads the
# current content, yields it to the caller's block, and appends whatever the block
# returns. A block returning nil is a refusal: nothing is written. Read, decide, and
# append happen inside one lock hold on purpose (spec "Approach"): that is what makes
# "is this subject already running" and "append running" atomic against a second
# writer, which a check followed by a separate append could never be.
#
# Pure and dependency-injected: `flock:` and `sleeper:` are constructor-style test
# seams (never an environment variable, never a global); this module reads no
# environment variable and shells out to nothing.
module GuardedAppend
  # Raised when the lock could not be taken within `retries` attempts (real
  # contention), or when flock itself is unsupported on this filesystem and
  # `strict: true` (spec D12a). Nothing is written either way; the caller is told
  # plainly that nothing landed and must retry.
  class Unavailable < StandardError; end

  module_function

  # Five attempts, 20 ms apart: about 100 ms of wall time total (spec D12).
  DEFAULT_RETRIES = 5
  DEFAULT_BACKOFF = 0.02

  # Default lock and sleep seams: a real flock call, a real sleep. Tests inject
  # replacements to simulate contention, recovery, and a flock-less filesystem
  # hermetically, with no need for a real flock-less mount or a slow test run.
  DEFAULT_FLOCK = ->(handle, mode) { handle.flock(mode) }
  private_constant :DEFAULT_FLOCK

  DEFAULT_SLEEPER = ->(seconds) { sleep(seconds) }
  private_constant :DEFAULT_SLEEPER

  # Open `path` (creating it if absent, never truncating it), take an exclusive
  # non-blocking lock with up to `retries` attempts (`backoff` seconds apart), and
  # under that one hold read the file's current content, yield it to the block, and
  # append what the block returns.
  #
  # Returns :written when a line was appended, :refused when the block returned nil
  # (nothing written, spec: a refusal). Raises Unavailable, writing nothing, when the
  # lock could not be taken within `retries` attempts.
  #
  # `strict:` decides what happens when flock itself raises a SystemCallError OTHER
  # than contention (EWOULDBLOCK/EAGAIN) - a filesystem without flock support,
  # distinct from real contention (spec D12a): strict (the default) raises
  # Unavailable; non-strict proceeds unguarded, since a single O_APPEND write still
  # lands whole there. The SystemCallError rescue wraps the flock call only (spec
  # D12b); an Errno::ENOENT from File.open (a missing parent directory) propagates
  # as itself, never read as Unavailable.
  def call(path, retries: DEFAULT_RETRIES, backoff: DEFAULT_BACKOFF, strict: true,
           flock: DEFAULT_FLOCK, sleeper: DEFAULT_SLEEPER, &block)
    handle = File.open(path, File::RDWR | File::APPEND | File::CREAT, 0o644)
    begin
      status = take_lock(handle, retries: retries, backoff: backoff, flock: flock, sleeper: sleeper)

      case status
      when :contended
        raise Unavailable, "could not take an exclusive lock on #{path} after #{retries} attempts"
      when :unsupported
        if strict
          raise Unavailable, "flock is unsupported on #{path} and strict: true refuses to proceed unguarded"
        end

        write_line(handle, &block)
      when :locked
        begin
          write_line(handle, &block)
        ensure
          unlock(handle, flock: flock)
        end
      end
    ensure
      handle.close
    end
  end

  # Attempt the lock up to `retries` times. Returns :locked, :unsupported (a
  # non-contention SystemCallError from flock, decided once, never retried), or
  # :contended (every attempt failed with EWOULDBLOCK/EAGAIN or a false return).
  # Sleeps `backoff` seconds after EVERY contended attempt, including the last, so
  # the total backoff budget is exactly `retries` sleeps (spec D12: "about 100 ms of
  # wall time in total" = 5 attempts * 20 ms, not 4).
  def take_lock(handle, retries:, backoff:, flock:, sleeper:)
    status = :contended
    retries.times do
      status = try_flock(handle, flock)
      return status unless status == :contended

      sleeper.call(backoff)
    end
    status
  end
  private_class_method :take_lock

  # One attempt at the non-blocking exclusive lock. File#flock RAISES (does not
  # return false) for every errno except EWOULDBLOCK/EAGAIN on most platforms, so
  # both the "returns false" and the "raises EWOULDBLOCK" shapes read as contention;
  # any other SystemCallError means flock is not supported on this filesystem.
  def try_flock(handle, flock)
    result = flock.call(handle, File::LOCK_EX | File::LOCK_NB)
    result == false ? :contended : :locked
  rescue Errno::EWOULDBLOCK, Errno::EAGAIN
    :contended
  rescue SystemCallError
    :unsupported
  end
  private_class_method :try_flock

  # Read the current content, yield it to the block, and write what it returns. A
  # block returning nil writes nothing and reports :refused. Before a real write, if
  # the content is non-empty and does not end in a newline, a newline is written
  # first (spec D9a): a crash that truncated the previous write must not glue the
  # next transition onto its tail. The handle is opened O_APPEND, so every write
  # lands at the current end of file regardless of the read's cursor position.
  def write_line(handle, &block)
    content = handle.read
    line = block.call(content)
    return :refused if line.nil?

    prefix = !content.empty? && !content.end_with?("\n") ? "\n" : ""
    handle.write("#{prefix}#{line}")
    handle.flush
    :written
  end
  private_class_method :write_line

  def unlock(handle, flock:)
    flock.call(handle, File::LOCK_UN)
  rescue SystemCallError
    nil
  end
  private_class_method :unlock
end
