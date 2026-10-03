# frozen_string_literal: true

require "fileutils"
require_relative "bundle"

module InstallerRelease
  # Installs one verified release: checks its manifest against the requested
  # release, stages it, installs its runtime gems, then switches to it. A
  # release that is already installed is switched to without staging.
  class ReleaseInstall
    def initialize(home:, bundle: Bundle.new)
      @activation = Activation.new(home: home)
      @home = home
      @bundle = bundle
    end

    def call(archive:, manifest:, expected:)
      Manifest.check(manifest, archive: archive, expected_release: expected)
      version = expected.fetch("version")
      return activation.switch(version) if activation.installed?(version)

      stage(archive, manifest, expected) { |candidate| activate(candidate, version) }
    end

    private

    attr_reader :activation, :home, :bundle

    def stage(archive, manifest, expected)
      FileUtils.mkdir_p(home)
      candidate = Staging.create(archive: archive, manifest: manifest, parent: home, expected_release: expected)
      yield candidate
    ensure
      FileUtils.rm_rf(File.dirname(candidate)) if candidate
    end

    def activate(candidate, version)
      activation.activate(candidate, version: version, before_switch: -> { bundle.call(activation.release_path(version)) })
    end
  end
end
