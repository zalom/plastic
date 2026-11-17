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
      def initialize(package, record, statusline: nil)
        super(package, record)
        @statusline = statusline
      end

      private

      def copy
        FileUtils.mkdir_p(hooks_dir)
        hooks + skills(exclude: advisor_exclusions) + role_files
      end

      def integrate
        root = record.root
        LegacyPlugin.new(root).call
        hooks = ClaudeHooks.new(package, root)
        keep_status_line? ? hooks.merge_keeping_status_line(settings_path) : hooks.merge(settings_path)
        EnginePermissions.merge_file(settings_path)
        MarkedSection.new(MarkedSection::CLAUDE, CompactInstructions::BODY).inject(File.join(root, "CLAUDE.md"))
        {}
      end

      def settings_path = File.join(record.root, "settings.json")

      def hooks_dir = File.join(record.root, "hooks")

      def hooks
        Dir.glob(File.join(package.root, "hooks", "*")).select { |path| File.file?(path) }.filter_map { |path| hook(path) }
      end

      def hook(source)
        name = File.basename(source)
        target = File.join(hooks_dir, name.start_with?("plastic-") ? name : "plastic-#{name}")
        return drop_status_line(target) if name.end_with?("statusline") && !package.choices.statusline?

        FileUtils.cp(source, target)
        FileUtils.chmod(0o755, target)
        target
      end

      def drop_status_line(target)
        return unless File.exist?(target)

        FileUtils.rm_f(target)
        puts "  Status line removed. To turn it on: plastic config set statusline true"
      end

      def keep_status_line?
        return @statusline == :keep if @statusline

        command = Hash(Files.read_json(settings_path))["statusLine"]&.fetch("command", nil)
        !command.nil? && !HookRegistry.claude_purge_command?(command)
      end
    end
  end
end
