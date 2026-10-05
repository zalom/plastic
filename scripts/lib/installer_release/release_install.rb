# frozen_string_literal: true

require "fileutils"
require "shellwords"
require_relative "bundle"
require_relative "rubies"

module InstallerRelease
  # Installs one verified release: checks its manifest against the requested
  # release, chooses the Ruby it runs on, stages it with a launcher bound to
  # that Ruby, installs its runtime gems, then switches to it. A release that
  # is already installed is switched to without staging. The switch syncs the
  # home through the given home sync.
  class ReleaseInstall
    def initialize(home:, bundle: Bundle.new, sync: NoSync, choice: RubyChoice.new(home: home))
      @activation = Activation.new(home: home, sync: sync)
      @home = home
      @bundle = bundle
      @choice = choice
    end

    def call(archive:, manifest:, expected:)
      Manifest.check(manifest, archive: archive, expected_release: expected)
      version = expected.fetch("version")
      return activation.switch(version) if activation.releases.installed?(version)

      stage(archive, version) { |candidate| activate(candidate, version, choice.call(manifest)) }
    end

    private

    attr_reader :activation, :home, :bundle, :choice

    def stage(archive, version)
      FileUtils.mkdir_p(home)
      candidate = Staging.create(archive: archive, version: version, parent: home)
      begin
        yield candidate
      ensure
        FileUtils.rm_rf(File.dirname(candidate))
      end
    end

    def activate(candidate, version, ruby)
      path = activation.releases.path(version)
      ReleaseLauncher.write(candidate, ruby, path)
      activation.activate(candidate, version: version, before_switch: -> { bundle.call(path, ruby) })
    end
  end

  # The launcher of a release: a shell script that starts the release's Ruby
  # by its full path, so it runs the same Ruby whatever PATH holds. The Ruby
  # entry point moves to libexec/plastic.
  module ReleaseLauncher
    def self.write(candidate, ruby, release_path)
      launcher = move_entry(candidate)
      entry = Shellwords.escape(File.join(release_path, "libexec", "plastic"))
      File.write(launcher, "#!/bin/sh\nexec #{Shellwords.escape(ruby.path)} --disable-gems #{entry} \"$@\"\n")
      File.chmod(0o755, launcher)
    end

    def self.move_entry(candidate)
      launcher = File.join(candidate, "bin", "plastic")
      FileUtils.mkdir_p(File.join(candidate, "libexec"))
      File.rename(launcher, File.join(candidate, "libexec", "plastic"))
      launcher
    end
  end
end
