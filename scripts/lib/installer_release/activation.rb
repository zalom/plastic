# frozen_string_literal: true

require "fileutils"
require "securerandom"

module InstallerRelease
  class ActivationError < StandardError; end

  class Activation
    def initialize(home:)
      @home = home
    end

    def activate!(candidate, version:, before_switch: nil)
      Candidate.validate!(candidate, version)
      with_lock { publish!(candidate, version, before_switch) }
      version
    rescue => error
      raise error if error.is_a?(ActivationError)

      raise ActivationError, error.message
    end

    def rollback!
      with_lock { switch_to!(previous_version || raise(ActivationError, "no previous release is available")) }
      active_version
    end

    def active_path
      File.join(home, "active")
    end

    def active_version
      version_at(active_path)
    end

    def previous_version
      version_at(previous_path)
    end

    private

    attr_reader :home

    def publish!(candidate, version, before_switch)
      FileUtils.mkdir_p(releases_path)
      destination = File.join(releases_path, version)
      raise ActivationError, "release version already exists" if File.exist?(destination)

      File.rename(candidate, destination)
      before_switch&.call
      switch_to!(version)
    end

    def with_lock
      FileUtils.mkdir_p(home)
      File.open(File.join(home, "INSTALL.lock"), "a") do |lock|
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock&.flock(File::LOCK_UN)
      end
    end

    def switch_to!(version)
      candidate = File.join(releases_path, version)
      Candidate.validate!(candidate, version)
      replace_pointer(previous_path, active_version) if active_version && active_version != version
      replace_pointer(active_path, version)
    end

    def releases_path
      File.join(home, "releases")
    end

    def previous_path
      File.join(home, "previous")
    end

    def replace_pointer(path, version)
      temporary = "#{path}.#{SecureRandom.hex(8)}"
      File.symlink(File.join("releases", version), temporary)
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def version_at(pointer)
      version_path = File.join(pointer, "VERSION")
      File.file?(version_path) ? File.read(version_path).strip : nil
    end
  end
end
