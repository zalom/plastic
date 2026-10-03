# frozen_string_literal: true

require_relative "flat_share"
require_relative "install_lock"
require_relative "journal"

module InstallerRelease
  # One activation step under the installer lock. It first restores what a
  # stopped installer left, moves a flat share into the releases layout,
  # and then runs the step with a journal open: the step completes, or the
  # journal puts the pointers, the releases and the home back.
  class Transaction
    def initialize(home, releases, journal)
      @home = home
      @releases = releases
      @journal = journal
    end

    def run(&)
      as_activation_error do
        InstallLock.hold(home) do
          journal.recover
          FlatShare.new(home, releases).migrate
          journaled(&)
        end
      end
    end

    private

    attr_reader :home, :releases, :journal

    def journaled
      journal.open
      yield.tap { journal.discard }
    rescue
      journal.restore
      raise
    end

    def as_activation_error
      yield
    rescue ActivationError
      raise
    rescue => error
      raise ActivationError, error.message
    end
  end
end
