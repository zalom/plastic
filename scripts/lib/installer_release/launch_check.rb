# frozen_string_literal: true

require "json"
require "open3"

module InstallerRelease
  # Starts the launcher of a release and reads the version it reports, so a
  # release that cannot start, or reports another version, is never switched
  # to. The launcher runs without the bundle of the process that called it.
  class LaunchCheck
    RUN = ->(env, command) { Open3.capture3(env, *command) }
    CLEAN = %w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION].to_h { |name| [name, nil] }.freeze

    # What the launcher of a version printed, and what is wrong with it.
    Report = Data.define(:version, :out, :err) do
      def problem
        reported = reported_version
        return ["does not start", err.strip].reject(&:empty?).join(": ") if reported == :unreadable

        "reports #{reported || "no version"}" unless reported == version
      end

      def reported_version
        JSON.parse(out).dig("result", "version")
      rescue JSON::ParserError
        :unreadable
      end
    end

    def initialize(run: RUN)
      @run = run
    end

    def call(release_path, version)
      out, err, = run.call(CLEAN, [File.join(release_path, "bin", "plastic"), "version", "--json"])
      problem = Report.new(version:, out:, err:).problem
      raise VerificationError, "the launcher of #{version} #{problem}" if problem

      true
    end

    private

    attr_reader :run
  end
end
