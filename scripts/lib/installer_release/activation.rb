# frozen_string_literal: true

require "fileutils"
require_relative "journal"
require_relative "placement"
require_relative "pointer"
require_relative "releases"
require_relative "transaction"

module InstallerRelease
  class ActivationError < StandardError; end

  # The home sync of an activation that writes nothing outside the share.
  module NoSync
    def self.paths = []

    def self.call = nil
  end

  # Keeps each release in its own directory under releases/ and switches the
  # active and previous pointers between them, then syncs the home files of
  # the release it switched to. Each activation, switch and rollback is one
  # transaction under the installer lock: it completes, or the journal puts
  # the pointers, the releases and the home back as they were.
  class Activation
    attr_reader :releases

    def initialize(home:, releases: Releases.new(home), sync: NoSync)
      @home = home
      @releases = releases
      @sync = sync
      @transaction = Transaction.new(home, releases, Journal.new(home, releases, sync.method(:paths)))
    end

    def activate(candidate, version:, before_switch: nil)
      placement = Placement.new(candidate, releases.path(version))
      transaction.run { publish(placement, before_switch) }
      version
    end

    def rollback = switch(previous_version || raise(ActivationError, "no previous release is available"))

    def switch(version)
      raise ActivationError, "#{version} is not installed" unless releases.installed?(version)

      transaction.run { switch_to(version) }
      active_version
    end

    def recover = transaction.run { nil }

    def active_path = File.join(home, "active")

    def previous_path = File.join(home, "previous")

    def active_version = Pointer.new(active_path).version

    def previous_version = Pointer.new(previous_path).version

    private

    attr_reader :home, :sync, :transaction

    def publish(placement, before_switch)
      place(placement)
      before_switch&.call
      switch_to(placement.version)
    rescue
      placement.undo
      raise
    end

    def place(placement)
      placement.check
      FileUtils.mkdir_p(releases.root)
      raise ActivationError, "candidate is not on the installation filesystem" unless releases.same_filesystem?(placement.candidate)

      placement.move
    end

    def switch_to(version)
      Candidate.check(releases.path(version), version)
      move_pointers(version)
      sync.call
    end

    def move_pointers(version)
      current = active_version
      replace_pointer(previous_path, current) if current && current != version
      replace_pointer(active_path, version)
    end

    def replace_pointer(path, version)
      Pointer.new(path).point_to(releases.pointer_target(version))
    end
  end
end
