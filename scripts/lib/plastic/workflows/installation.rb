# frozen_string_literal: true

require "json"
require "pathname"
require "stringio"
require_relative "../../../install"

module Plastic
  module Workflows
    # The installer as the installer commands see it: the running package, the
    # home it installs into and the agent folders under the person's home.
    # The installer prints with puts, so `capture` hands its lines back to the
    # call that prints them.
    class Installation < ::Install
      PACKAGE_ROOT = File.expand_path("../../../..", __dir__)
      SOURCES = %w[VERSION package.json].freeze
      AGENT_KEYS = %w[claude codex hermes].freeze
      FOLDERS = %i[dir home_dir].freeze
      INSTALLER = "curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh |"

      def self.of(context)
        scope = context.scope
        new(package_root: package_root(scope), plastic_home: scope.plastic_home,
          agents: InstallerCore::DEFAULT_AGENTS.map { |agent| rehome(agent, scope.home) })
      end

      def self.package_root(scope) = scope.setting("PLASTIC_PACKAGE_ROOT", PACKAGE_ROOT)

      def self.source(root) = SOURCES.map { |name| File.join(root, name) }.find { |path| File.file?(path) }

      def self.rehome(agent, home)
        agent.to_h { |key, value| [key, FOLDERS.include?(key) ? File.join(home, Pathname(value).relative_path_from(Dir.home).to_s) : value] }
      end

      def self.selected(context)
        return AGENT_KEYS if context.all

        chosen = AGENT_KEYS.select { |key| context.public_send(key) }
        chosen.empty? ? ["claude"] : chosen
      end

      # A reinstall that names no agent syncs the agents already registered.
      def self.to_install(context)
        named = context.all || AGENT_KEYS.any? { |key| context.public_send(key) }
        registered = (context.reinstall && !named) ? of(context).installed_agents : []
        registered.empty? ? selected(context) : registered
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

      def planned_removals(keys) = keys.filter_map { |key| agent_config(key) }.flat_map { |config| agent_files(config) }

      def agent_files(config) = manifest_files(manifest_path_for(nil, config)).grep(->(file) { File.exist?(file) }) + [record_dir_for(config)]

      def unregistered(keys) = keys.reject { |key| agent_installed?(key) }

      def install(selected, reinstall:, force:)
        fresh = (reinstall || !installed?) ? selected : unregistered(selected)
        run(selected: fresh, force:, reinstall:, argv: [], input: StringIO.new, already_registered: selected - fresh)
      end

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
