# frozen_string_literal: true

require "fileutils"
require "shellwords"
require_relative "bundle"

module InstallerRelease
  # Installs one verified release: checks its manifest against the requested
  # release, chooses the Ruby it runs on, stages it with a launcher bound to
  # that Ruby, installs its runtime gems, then switches to it. A release that
  # is already installed is switched to without staging. The switch syncs the
  # home through the given home sync.
  class ReleaseInstall
    def initialize(home:, bundle: Bundle.new, sync: NoSync, ruby: Ruby.chosen)
      @activation = Activation.new(home: home, sync: sync)
      @home = home
      @bundle = bundle
      @ruby = ruby
    end

    def call(archive:, manifest:, expected:)
      Manifest.check(manifest, archive: archive, expected_release: expected)
      version = expected.fetch("version")
      return relaunch(version) if activation.releases.installed?(version)

      stage(archive, version) { |candidate| activate(candidate, version) }
    end

    private

    attr_reader :activation, :home, :bundle, :ruby

    def relaunch(version)
      ReleaseLauncher.write(activation.releases.path(version), ruby, activation.releases.path(version))
      activation.switch(version)
    end

    def stage(archive, version)
      FileUtils.mkdir_p(home)
      candidate = Staging.create(archive: archive, version: version, parent: home)
      begin
        yield candidate
      ensure
        FileUtils.rm_rf(File.dirname(candidate))
      end
    end

    def activate(candidate, version)
      path = activation.releases.path(version)
      ReleaseLauncher.write(candidate, ruby, path)
      activation.activate(candidate, version: version, before_switch: -> { bundle.call(path, ruby) })
    end
  end

  # The launcher of a release: a shell script, bin/plastic, that starts the
  # release's exe/plastic with the release's Ruby by its full path, so it runs
  # the same Ruby whatever PATH holds. It replaces the bin/plastic the archive
  # carries, and bin/ruby starts the same Ruby for the hooks.
  module ReleaseLauncher
    GONE = "plastic: %s is gone; run install.sh again: curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh"

    def self.write(candidate, ruby, release_path)
      FileUtils.mkdir_p(File.join(candidate, "bin"))
      start = Shellwords.escape(ruby.path)
      entry = Shellwords.escape(File.join(release_path, "exe", "plastic"))
      script(File.join(candidate, "bin", "plastic"), "#{start} --disable-gems -rrbconfig #{entry}", guard(ruby.path))
      script(File.join(candidate, "bin", "ruby"), start, "")
    end

    def self.guard(ruby)
      "[ -x #{Shellwords.escape(ruby)} ] || { echo #{Shellwords.escape(format(GONE, ruby))} >&2; exit 1; }\n"
    end

    def self.script(path, command, guard)
      File.write(path, "#!/bin/sh\n#{guard}exec #{command} \"$@\"\n")
      File.chmod(0o755, path)
    end
  end
end
