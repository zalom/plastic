# frozen_string_literal: true

require "fileutils"
require_relative "placement"
require_relative "pointer"
require_relative "releases"

module InstallerRelease
  class ActivationError < StandardError; end

  # Keeps each release in its own directory under releases/ and switches the
  # active and previous pointers between them, one installer at a time.
  class Activation
    attr_reader :releases

    def initialize(home:, releases: Releases.new(home))
      @home = home
      @releases = releases
    end

    def activate(candidate, version:, before_switch: nil)
      placement = Placement.new(candidate, releases.path(version))
      as_activation_error { with_lock { publish(placement, before_switch) } }
      version
    end

    def rollback = switch(previous_version || raise(ActivationError, "no previous release is available"))

    def switch(version)
      raise ActivationError, "#{version} is not installed" unless releases.installed?(version)

      with_lock { switch_to(version) }
      active_version
    end

    def active_path = File.join(home, "active")

    def previous_path = File.join(home, "previous")

    def active_version = Pointer.new(active_path).version

    def previous_version = Pointer.new(previous_path).version

    private

    attr_reader :home

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
      FileUtils.mkdir_p(releases.root)
      raise ActivationError, "candidate is not on the installation filesystem" unless releases.same_filesystem?(placement.candidate)

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
      Candidate.check(releases.path(version), version)
      Pointer.new(previous_path).keep { move_pointers(version) }
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
