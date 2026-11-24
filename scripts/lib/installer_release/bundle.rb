# frozen_string_literal: true

require "rbconfig"

module InstallerRelease
  # One Ruby a release runs on, by the full path of its ruby program.
  Ruby = Data.define(:path) do
    def bundle = File.join(File.dirname(path), "bundle")

    # The developer's PLASTIC_RUBY, else the Ruby that is running the installer.
    def self.chosen(override = "") = new(override.to_s.then { |path| path.empty? ? RbConfig.ruby : path })
  end

  # Installs a release's runtime gems into the release itself as a
  # standalone bundle, which the launcher loads without RubyGems. The
  # bundle program and the gems come from the Ruby the release runs on.
  class Bundle
    RUN = ->(env, command) { system(env, *command, exception: true) }
    SAY = ->(text) { warn(text) }
    LEFT_OUT = "plastic console needs a C compiler (Xcode command line tools with the licence accepted, or build-essential). " \
      "The install left it out; every other command works. Install a compiler and run the installer again to add it."

    def initialize(run: RUN, say: SAY)
      @runner = run
      @say = say
    end

    def call(release_path, ruby)
      runtime = File.join(release_path, "runtime")
      return false unless File.file?(File.join(runtime, "Gemfile"))

      install(self.class.environment(runtime, ruby), ruby)
      true
    end

    def self.environment(runtime, ruby)
      { "BUNDLE_GEMFILE" => File.join(runtime, "Gemfile"), "BUNDLE_PATH" => File.join(runtime, "bundle"),
        "BUNDLE_APP_CONFIG" => File.join(runtime, ".bundle"), "BUNDLE_FROZEN" => "true", "BUNDLE_VERSION" => "system",
        "GEM_HOME" => nil, "GEM_PATH" => nil, "PATH" => [File.dirname(ruby.path), ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR) }
    end

    private

    attr_reader :runner, :say

    # The console group needs a compiler on some machines. When the install fails, it runs once more without that group.
    def install(env, ruby)
      command = [ruby.bundle, "install", "--standalone", "--quiet"]
      runner.call(env, command)
    rescue RuntimeError
      runner.call(env.merge("BUNDLE_WITHOUT" => "console"), command)
      say.call(LEFT_OUT)
    end
  end
end
