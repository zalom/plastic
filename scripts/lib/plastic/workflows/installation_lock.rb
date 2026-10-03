# frozen_string_literal: true

module Plastic
  module Workflows
    # Reads the installer lock of a share: free, held by a running
    # installer, or left behind by an interrupted activation.
    class InstallationLock
      LABEL = "installer lock:"
      INTERRUPTED = "run the installer again; it restores the interrupted activation before it changes anything"

      def initialize(share)
        @share = share
      end

      def check
        return InstallationHealth::Check.new(LABEL, "an activation was interrupted", INTERRUPTED) if interrupted?

        InstallationHealth::Check.new(LABEL, held? ? "held by a running installer" : "free", nil)
      end

      private

      attr_reader :share

      def interrupted? = File.directory?(File.join(share, "activation"))

      def held?
        lock_file = File.join(share, "INSTALL.lock")
        File.file?(lock_file) && File.open(lock_file) { |file| !file.flock(File::LOCK_SH | File::LOCK_NB) }
      end
    end
  end
end
