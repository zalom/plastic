# frozen_string_literal: true

require_relative "agent_install"
require_relative "claude_hooks"
require_relative "compact_instructions"
require_relative "engine_permissions"
require_relative "legacy_plugin"
require_relative "marked_section"
require_relative "role_files"

module Plastic
  module Installations
    # The install for Claude Code: hook launchers, skills, agent role files,
    # then the hooks, deny rules and instruction block merged into the files
    # of the person. A status line of the person stays unless Plastic wrote it
    # or the person chose Plastic's.
    class ClaudeInstall < AgentInstall
      SCRIPTS = "$SCRIPT_DIR/../scripts/"
      INSTALLED_SCRIPTS = "$HOME/.plastic/scripts/"

      def initialize(package, record, statusline: nil)
        super(package, record)
        @statusline = statusline
      end

      private

      def copy
        choices = @package.choices
        FileUtils.mkdir_p(hooks_dir)
        hooks + skills(exclude: advisor_exclusions) +
          RoleFiles.new(@package.root).call(File.join(@record.root, "agents"), models: choices.models, efforts: choices.efforts, advisor: choices.advisor?)
      end

      def integrate
        LegacyPlugin.new(@record.root).call
        ClaudeHooks.new(@package, @record.root).merge(settings_path, choice: choice)
        EnginePermissions.merge_file(settings_path)
        MarkedSection.new(MarkedSection::CLAUDE, CompactInstructions::BODY).inject(File.join(@record.root, "CLAUDE.md"))
        {}
      end

      def settings_path = File.join(@record.root, "settings.json")

      def hooks_dir = File.join(@record.root, "hooks")

      def hooks
        Dir.glob(File.join(@package.root, "hooks", "*")).select { |path| File.file?(path) }.filter_map { |path| hook(path) }
      end

      def hook(source)
        name = File.basename(source)
        target = File.join(hooks_dir, name.start_with?("plastic-") ? name : "plastic-#{name}")
        return drop_status_line(target) if name.end_with?("statusline") && !@package.choices.statusline?

        File.write(target, File.read(source).gsub(SCRIPTS, INSTALLED_SCRIPTS))
        FileUtils.chmod(0o755, target)
        target
      end

      def drop_status_line(target)
        return unless File.exist?(target)

        FileUtils.rm_f(target)
        puts "  Status line removed. To turn it on: plastic config set statusline true"
      end

      def choice
        return @statusline if @statusline

        command = Hash(Files.read_json(settings_path))["statusLine"]&.fetch("command", nil)
        command.nil? || HookRegistry.claude_purge_command?(command) ? :plastic : :keep
      end
    end
  end
end
