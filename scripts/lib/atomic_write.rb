# encoding: UTF-8
# frozen_string_literal: true

# AtomicWrite (intent 334, n2, D19r): a sibling-temp-plus-rename write, the
# same shape as Lock#write (scripts/lib/lock.rb) - a content write is never
# an in-place truncate, so a crash mid-write can never leave an empty or
# half-written target on disk. The temp file is a SIBLING in the same
# directory as the target, never a system tmpdir, because File.rename can
# raise EXDEV when the temp and the target live on different filesystems.
#
# The renamer is injectable so the interrupted-write case (a rename that
# raises) is testable with dependency injection, never eval or a global
# (D19r).
module AtomicWrite
  module_function

  def write(path, content, renamer: File.method(:rename))
    dir = File.dirname(path)
    temp = File.join(dir, ".#{File.basename(path)}.tmp.#{Process.pid}.#{Time.now.to_f}.#{rand(0xFFFFFF)}")
    File.write(temp, content)
    renamer.call(temp, path)
    true
  rescue StandardError
    File.delete(temp) if temp && File.exist?(temp)
    raise
  end
end
