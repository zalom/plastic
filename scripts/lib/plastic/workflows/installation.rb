# frozen_string_literal: true

require "json"
require "pathname"
require "stringio"
require_relative "../../../install"
require_relative "../harnesses"
require_relative "../installations"

module Plastic
  module Workflows
    # The installer as the installer commands see it: the running package, the
    # home it installs into and the agent folders under the person's home.
    # The installer prints with puts, so `capture` hands its lines back to the
    # call that prints them.
    class Installation < ::Install
      PACKAGE_ROOT = File.expand_path("../../../..", __dir__)
      SOURCES = %w[VERSION package.json].freeze
      FOLDERS = %i[dir home_dir].freeze
      INSTALLER = "curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh |"

      def self.of(context) = for_scope(context.scope)

      def self.for_scope(scope)
        new(package_root: package_root(scope), plastic_home: scope.plastic_home,
          agents: InstallerCore::DEFAULT_AGENTS.map { |agent| rehome(agent, scope.home) })
      end

      def self.running(scope) = source(package_root(scope)) && for_scope(scope).version

      def self.package_root(scope) = scope.setting("PLASTIC_PACKAGE_ROOT", PACKAGE_ROOT)

      def self.source(root) = SOURCES.map { |name| File.join(root, name) }.find { |path| File.file?(path) }

      def self.rehome(agent, home)
        agent.to_h { |key, value| [key, FOLDERS.include?(key) ? File.join(home, Pathname(value).relative_path_from(Dir.home).to_s) : value] }
      end

      def self.fetch_command(setting) = "#{INSTALLER} #{setting} sh"

      def read_package_version(root)
        path = self.class.source(root)
        text = File.read(path)
        path.end_with?(".json") ? JSON.parse(text).fetch("version") : text.strip
      end

      def channel = channel_for(version)

      def newer? = semver_gt?(version, installed_version)

      def planned_files
        core_files.filter_map do |source, destination|
          [File.exist?(File.join(plastic_home, destination)) ? "replace" : "add", destination] if File.exist?(File.join(package_root, source))
        end
      end

      def synced = installed_agents.select { |key| Harnesses.installed_by(key) }

      def kept(harnesses) = (Installations.recorded(plastic_home) | installed_agents.map { |key| Harnesses.installed_by(key).name }) - harnesses

      def install(keys, reinstall:, force:) = run(selected: keys, force:, reinstall:, argv: [], input: StringIO.new)

      def wire(keys) = install(keys, reinstall: false, force: false)

      def preflight
        report = StringIO.new
        [preflight_gate(out: report).zero?, report.string.lines(chomp: true)]
      end

      def self.capture
        saved = $stdout
        $stdout = StringIO.new
        yield
        $stdout.string.lines(chomp: true)
      ensure
        $stdout = saved
      end
    end
  end
end
