# frozen_string_literal: true

require "rbconfig"

module InstallerRelease
  # One Ruby a release runs on, by the full path of its ruby program.
  Ruby = Data.define(:path) do
    def bundle = File.join(File.dirname(path), "bundle")

    # The developer's PLASTIC_RUBY, else the Ruby that is running the installer.
    def self.chosen(override = "") = new(override.to_s.empty? ? RbConfig.ruby : override.to_s)
  end

  # Installs a release's runtime gems into the release itself as a
  # standalone bundle, which the launcher loads without RubyGems. The
  # bundle program and the gems come from the Ruby the release runs on.
  class Bundle
    RUN = ->(env, command) { system(env, *command, exception: true) }

    def initialize(run: RUN)
      @run = run
    end

    def call(release_path, ruby)
      runtime = File.join(release_path, "runtime")
      return false unless File.file?(File.join(runtime, "Gemfile"))

      run.call(self.class.environment(runtime, ruby), [ruby.bundle, "install", "--standalone", "--quiet"])
      true
    end

    def self.environment(runtime, ruby)
      { "BUNDLE_GEMFILE" => File.join(runtime, "Gemfile"), "BUNDLE_PATH" => File.join(runtime, "bundle"),
        "BUNDLE_APP_CONFIG" => File.join(runtime, ".bundle"), "BUNDLE_FROZEN" => "true", "BUNDLE_VERSION" => "system",
        "GEM_HOME" => nil, "GEM_PATH" => nil, "PATH" => [File.dirname(ruby.path), ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR) }
    end

    private

    attr_reader :run
  end
end
