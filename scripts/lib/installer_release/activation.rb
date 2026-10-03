# frozen_string_literal: true

require "fileutils"
require_relative "placement"
require_relative "pointer"

module InstallerRelease
  class ActivationError < StandardError; end

  # Keeps each release in its own directory under releases/ and switches the
  # active and previous pointers between them, one installer at a time.
  class Activation
    def initialize(home:)
      @home = home
      @releases = File.join(home, "releases")
    end

    def activate(candidate, version:, before_switch: nil)
      placement = Placement.new(candidate, File.join(releases, version))
      as_activation_error { with_lock { publish(placement, before_switch) } }
      version
    end

    def rollback = switch(previous_version || raise(ActivationError, "no previous release is available"))

    def switch(version)
      raise ActivationError, "#{version} is not installed" unless installed?(version)

      with_lock { switch_to(version) }
      active_version
    end

    def installed?(version) = File.directory?(release_path(version))

    def release_path(version) = File.join(releases, version)

    def versions = File.directory?(releases) ? Dir.children(releases).sort : []

    def active_path = File.join(home, "active")

    def previous_path = File.join(home, "previous")

    def active_version = Pointer.new(active_path).version

    def previous_version = Pointer.new(previous_path).version

    private

    attr_reader :home, :releases

    def as_activation_error
      yield
    rescue ActivationError
      raise
    rescue => error
      raise ActivationError, error.message
    end

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
      FileUtils.mkdir_p(releases)
      raise ActivationError, "candidate is not on the installation filesystem" unless same_filesystem?(placement.candidate)

      placement.move
    end

    def with_lock
      FileUtils.mkdir_p(home)
      File.open(File.join(home, "INSTALL.lock"), "a") do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    def switch_to(version)
      Candidate.check(File.join(releases, version), version)
      Pointer.new(previous_path).keep { move_pointers(version) }
    end

    def move_pointers(version)
      current = active_version
      replace_pointer(previous_path, current) if current && current != version
      replace_pointer(active_path, version)
    end

    def same_filesystem?(candidate)
      File.stat(candidate).dev == File.stat(releases).dev
    end

    def replace_pointer(path, version)
      Pointer.new(path).point_to(File.join(File.basename(releases), version))
    end
  end
end
