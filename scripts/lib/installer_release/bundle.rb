# frozen_string_literal: true

module InstallerRelease
  # Installs a release's runtime gems into the release itself as a
  # standalone bundle, which the launcher loads without RubyGems.
  class Bundle
    RUN = ->(env, command) { system(env, *command, exception: true) }

    def initialize(run: RUN)
      @run = run
    end

    def call(release_path)
      runtime = File.join(release_path, "runtime")
      return false unless File.file?(File.join(runtime, "Gemfile"))

      run.call(self.class.environment(runtime), %w[bundle install --standalone --quiet])
      true
    end

    def self.environment(runtime)
      { "BUNDLE_GEMFILE" => File.join(runtime, "Gemfile"), "BUNDLE_PATH" => File.join(runtime, "bundle"),
        "BUNDLE_APP_CONFIG" => File.join(runtime, ".bundle"), "BUNDLE_FROZEN" => "true" }
    end

    private

    attr_reader :run
  end
end
