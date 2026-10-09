# frozen_string_literal: true

require_relative "ownership"

module Plastic
  module Hooks
    # The harness entries the installer writes: one hook group per event,
    # plus the status line and the screens, from `config.yml`. A rerun
    # replaces this installation's own groups and keeps everyone else's,
    # so a user's own hook or status line is never touched.
    class Entries
      EVENTS = { "SessionStart" => "hook resume --harness %s", "Stop" => "hook record --harness %s", "SessionEnd" => "hook end" }.freeze

      # Former names the launchers this installation wrote before it moved,
      # so their groups are replaced, not kept beside the new ones.
      def initialize(command:, config:, launchers:, former: [])
        @command = command
        @config = config
        @launchers = launchers
        @ownership = Ownership.new([command, *former, *launchers.values])
      end

      # A new Claude Code settings hash, with this installation's hook groups,
      # status line and screens replaced.
      def claude(settings)
        rewritten = with_events(settings, own_groups("claude-code").merge("MessageDisplay" => screens_group))
        hooks = rewritten["hooks"].reject { |event, groups| event == "MessageDisplay" && groups.empty? }
        status_line(rewritten.merge("hooks" => hooks))
      end

      # A new Codex hooks.json hash. Codex has no status line or screen events.
      def codex(hooks_json) = with_events(hooks_json, own_groups("codex"))

      # True when the command runs this installation's launcher, or one an
      # earlier install wrote, so an uninstall removes it.
      def own?(command) = @ownership.own?(command)

      private

      def with_events(settings, own)
        kept = Hash(settings["hooks"]).transform_values { |entries| without_ours(entries) }
        settings.merge("hooks" => kept.merge(own) { |_event, theirs, ours| theirs + ours })
      end

      def own_groups(harness) = EVENTS.transform_values { |words| [group(%("#{@command}" #{format(words, harness)}))] }

      def group(line) = { "matcher" => "", "hooks" => [{ "type" => "command", "command" => "env -u RUBYOPT #{line} || true" }] }

      def without_ours(entries) = Array(entries).reject { |entry| ours?(entry) }

      def ours?(entry) = Array(entry["hooks"]).any? { |hook| own?(hook["command"].to_s) }

      # A status line the user set stays: only an empty or our own is written,
      # and only our own is removed.
      def status_line(settings)
        foreign = settings.dig("statusLine", "command").then { |command| command && !own?(command) }
        foreign ? settings : own_status_line(settings)
      end

      def own_status_line(settings)
        return settings.except("statusLine") unless screen?(:statusline)

        settings.merge("statusLine" => { "type" => "command", "command" => @launchers[:statusline] })
      end

      def screens_group = screen?(:screens) ? [group(%("#{@launchers[:screens]}"))] : []

      def screen?(key) = @launchers.key?(key) && @config.flag([key.to_s], default: true)
    end
  end
end
