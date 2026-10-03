# frozen_string_literal: true

require "json"
require_relative "../../installer_release"

module Plastic
  module Workflows
    # Reads the parts of an installation that a working `plastic` needs and
    # names a repair for each broken one. It reads files and changes none.
    class InstallationHealth
      Check = Data.define(:label, :value, :repair)
      HOOK_LAUNCHER = %r{"([^"]+/bin/plastic)" hook }
      REINSTALL = "run plastic install --reinstall to point the hooks at the active release"
      INTERRUPTED = "run the installer again; it restores the interrupted activation before it changes anything"
      INCOMPLETE = "switch to a complete release with plastic rollback or plastic update"

      def self.of(context, ruby_version: RUBY_VERSION)
        scope = context.scope
        home = scope.home
        new(share: scope.setting("PLASTIC_SHARE", File.join(home, ".local", "share", "plastic")),
          bin: scope.setting("PLASTIC_BIN", File.join(home, ".local", "bin")), path: scope.setting("PATH", ""), home:, ruby_version:)
      end

      def initialize(share:, bin:, path:, home:, ruby_version:)
        @share = share
        @bin = bin
        @path = path
        @home = home
        @ruby_version = ruby_version
      end

      def checks
        activation = InstallerRelease::Activation.new(home: share)
        active = activation.active_version
        return [Check.new("active:", "none; no release is activated", nil), ruby] unless active

        [Check.new("active:", active, nil), Check.new("previous:", activation.previous_version || "none", nil),
          launcher, ruby, bundle, hooks, lock]
      end

      private

      attr_reader :share, :bin, :path, :home, :ruby_version

      def active_launcher = File.join(share, "active", "bin", "plastic")

      def launcher
        expected = File.join(bin, "plastic")
        found = path.split(File::PATH_SEPARATOR).map { |entry| File.join(entry, "plastic") }.find { |file| File.executable?(file) }
        return Check.new("launcher:", found, nil) if found == expected

        Check.new("launcher:", found ? "#{found} runs first, not #{expected}" : "not on PATH",
          "put #{bin} first on PATH; the installer links the launcher there")
      end

      def ruby = Check.new("ruby:", ruby_version, (ruby_version.to_i >= 4) ? nil : "install Ruby 4.0 or later")

      def bundle
        setup = File.join(share, "active", "runtime", "bundle", "bundler", "setup.rb")
        File.file?(setup) ? Check.new("sqlite3 bundle:", "present", nil) : Check.new("sqlite3 bundle:", "missing (#{setup})", INCOMPLETE)
      end

      def hooks
        stray = hook_launchers.uniq - [active_launcher]
        return Check.new("hooks:", "none registered", nil) if hook_launchers.empty?
        return Check.new("hooks:", "point at the active release", nil) if stray.empty?

        Check.new("hooks:", "point at #{stray.join(", ")}", REINSTALL)
      rescue JSON::ParserError => error
        Check.new("hooks:", "#{error.message} is not valid JSON", "fix #{error.message} by hand")
      end

      def hook_launchers
        @hook_launchers ||= hook_files.flat_map { |file| strings(parse(file)) }.filter_map { |text| text[HOOK_LAUNCHER, 1] }
      end

      def hook_files = [File.join(home, ".claude", "settings.json"), File.join(home, ".codex", "hooks.json")].select { |file| File.file?(file) }

      def parse(file)
        JSON.parse(File.read(file))
      rescue JSON::ParserError
        raise JSON::ParserError, file
      end

      def strings(node)
        case node
        when Hash then strings(node.values)
        when Array then node.flat_map { |item| strings(item) }
        else [node.to_s]
        end
      end

      def lock
        return Check.new("installer lock:", "an activation was interrupted", INTERRUPTED) if File.directory?(File.join(share, "activation"))

        Check.new("installer lock:", held? ? "held by a running installer" : "free", nil)
      end

      def held?
        lock_file = File.join(share, "INSTALL.lock")
        File.file?(lock_file) && File.open(lock_file) { |file| !file.flock(File::LOCK_SH | File::LOCK_NB) }
      end
    end
  end
end
