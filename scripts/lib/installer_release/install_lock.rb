# frozen_string_literal: true

require "fileutils"

module InstallerRelease
  # One installer at a time. A second install, update or rollback that finds
  # the lock held stops at once and changes nothing.
  module InstallLock
    BUSY = "another Plastic installer is running (INSTALL.lock is held); wait for it to finish and run this again"

    def self.hold(home)
      FileUtils.mkdir_p(home)
      File.open(File.join(home, "INSTALL.lock"), "a") do |lock|
        raise ActivationError, BUSY unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        yield
      end
    end
  end
end
