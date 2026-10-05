# frozen_string_literal: true

require "fileutils"
require "securerandom"
require_relative "hook_strip"
require_relative "managed_home"

module InstallerRelease
  # Brings the home in line with the active release: links the launcher,
  # removes the hooks of earlier launchers, and runs the active release's
  # own reinstall when Plastic is installed in the home. A launcher the
  # user wrote, or one that points outside the share, stays as it is.
  class HomeSync
    RUN = ->(env, command) { system(env, *command, exception: true) }
    FOREIGN = "%s is not Plastic's launcher; it stays as it is. Run %s directly, or move it aside and run this again."

    def initialize(share:, home:, run: RUN, out: $stdout)
      @share = share
      @home = home
      @run = run
      @out = out
    end

    def paths = home.paths

    def call
      link_launcher
      return unless File.file?(File.join(plastic_home, "VERSION"))

      HookStrip.new(files: hook_files, launchers: [target, File.join(plastic_home, "bin", "plastic")]).call
      run.call(environment, [target, "install", "--reinstall"])
    end

    private

    attr_reader :share, :home, :run, :out

    def launcher = home.launcher

    def plastic_home = home.plastic_home

    def user_home = home.user_home

    def target = File.join(share, "active", "bin", "plastic")

    def hook_files = [File.join(user_home, ".claude", "settings.json"), File.join(user_home, ".codex", "hooks.json")]

    def environment = { "PLASTIC_HOME" => plastic_home, "HOME" => user_home, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }

    def link_launcher
      return out.puts(format(FOREIGN, launcher, target)) unless ours?

      FileUtils.mkdir_p(File.dirname(launcher))
      temporary = "#{launcher}.#{SecureRandom.hex(8)}"
      File.symlink(target, temporary)
      File.rename(temporary, launcher)
    end

    def ours?
      return !File.exist?(launcher) unless File.symlink?(launcher)

      File.expand_path(File.readlink(launcher), File.dirname(launcher)).start_with?("#{share}/")
    end
  end
end
