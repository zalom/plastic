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
      gemfile = File.join(runtime, "Gemfile")
      return false unless File.file?(gemfile)

      run.call(environment(runtime, gemfile), %w[bundle install --standalone --quiet])
      true
    end

    private

    attr_reader :run

    def environment(runtime, gemfile)
      { "BUNDLE_GEMFILE" => gemfile, "BUNDLE_PATH" => File.join(runtime, "bundle"),
        "BUNDLE_APP_CONFIG" => File.join(runtime, ".bundle"), "BUNDLE_FROZEN" => "true" }
    end
  end
end
