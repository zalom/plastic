# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "hook_strip"
require_relative "launcher_link"
require_relative "managed_home"
require_relative "pointer"

module InstallerRelease
  # Brings the home in line with the active release: links the launcher,
  # removes the hooks of earlier launchers, and runs the active release's
  # own reinstall when Plastic is installed in the home. The reinstall's
  # output prints without its next step, which the caller names. A launcher
  # the user wrote, or one that points outside the share, stays as it is.
  class HomeSync
    RUN = lambda do |env, command|
      output, status = Open3.capture2e(env, *command)
      [output, status.success?]
    end
    FAILED = "plastic install --reinstall failed; nothing was changed"
    TRAILER = /\A(next|because):/
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
      reinstall
    end

    private

    attr_reader :share, :home, :run, :out

    def launcher = home.launcher

    def plastic_home = home.plastic_home

    def user_home = home.user_home

    def target = File.join(share, "active", "bin", "plastic")

    def launcher_ours? = LauncherLink.new(launcher, share).ours?

    def hook_files = [File.join(user_home, ".claude", "settings.json"), File.join(user_home, ".codex", "hooks.json")]

    def environment = { "PLASTIC_HOME" => plastic_home, "HOME" => user_home, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }

    def reinstall
      output, success = run.call(environment, [target, "install", "--reinstall"])
      shown = output.lines.grep_v(TRAILER).join
      out.puts(shown) unless shown.empty?
      raise ActivationError, FAILED unless success
    end

    def link_launcher
      return out.puts(format(FOREIGN, launcher, target)) unless launcher_ours?

      FileUtils.mkdir_p(File.dirname(launcher))
      Pointer.new(launcher).point_to(target)
    end
  end
end
