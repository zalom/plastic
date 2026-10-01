# frozen_string_literal: true

module Plastic
  module Hooks
    # The harness entries the installer writes: one hook group per event,
    # plus the status line and the screens, from `config.yml`. A rerun
    # replaces this installation's own groups and keeps everyone else's,
    # so a user's own hook or status line is never touched.
    class Entries
      EVENTS = { "SessionStart" => "hook resume", "Stop" => "hook record", "SessionEnd" => "hook record --end" }.freeze
      OLD_MARKS = %w[plastic-hook plastic-continue plastic-record codex-hook].freeze

      def initialize(command:, config:, launchers:)
        @command = command
        @config = config
        @launchers = launchers
      end

      # A new Claude Code settings hash, with this installation's hook groups,
      # status line and screens replaced.
      def claude(settings)
        with_screens(with_status_line(with_hooks(settings, "claude-code")))
      end

      # A new Codex hooks.json hash. Codex has no status line or screen events.
      def codex(hooks_json) = { **hooks_json, "hooks" => rewritten_events(hooks_json["hooks"], "codex") }

      private

      def with_hooks(settings, harness) = settings.merge("hooks" => rewritten_events(settings["hooks"], harness))

      def rewritten_events(hooks, harness)
        kept = strip_ours(hooks || {})
        EVENTS.each_with_object(kept) { |(event, words), all| all[event] = [*all[event], group(words, harness)] }
      end

      def group(words, harness) = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => wrapped(%("#{@command}" #{words} --harness #{harness})) }] }

      def wrapped(line) = "env -u RUBYOPT #{line} || true"

      def strip_ours(hooks)
        hooks.to_h { |event, entries| [event, Array(entries).reject { |entry| ours?(entry) }] }
      end

      def ours?(entry) = Array(entry["hooks"]).any? { |hook| ours_command?(hook["command"].to_s) }

      def ours_command?(command)
        ours = [@command, @launchers[:statusline], @launchers[:screens]].compact
        ours.any? { |path| command.include?(%("#{path}")) } || OLD_MARKS.any? { |mark| command.include?(mark) }
      end

      def with_status_line(settings)
        return settings.merge("statusLine" => { "type" => "command", "command" => @launchers[:statusline] }) if screen?(:statusline)
        return settings unless ours_status_line?(settings)

        settings.except("statusLine")
      end

      def ours_status_line?(settings) = settings.dig("statusLine", "command") == @launchers[:statusline]

      def with_screens(settings)
        return screens_on(settings) if screen?(:screens)

        screens_off(settings)
      end

      def screens_on(settings)
        hooks = (settings["hooks"] || {}).merge("MessageDisplay" => [message_display_group])
        settings.merge("hooks" => hooks)
      end

      def screens_off(settings)
        kept = Array((settings["hooks"] || {})["MessageDisplay"]).reject { |entry| ours?(entry) }
        settings.merge("hooks" => (settings["hooks"] || {}).merge("MessageDisplay" => kept))
      end

      def message_display_group = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => wrapped(%("#{@launchers[:screens]}")) }] }

      def screen?(key) = @config.flag([key.to_s], default: true)
    end
  end
end
