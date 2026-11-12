# frozen_string_literal: true

require "json"

module Plastic
  module Installations
    # A harness settings hash with the entries a record lists taken out. A
    # group, an event or a key goes only when this edit left it empty.
    class SettingsEdit
      def self.put(hash, key, value) = value.empty? ? hash.except(key) : hash.merge(key => value)

      def initialize(record)
        @record = record
      end

      def call(settings)
        edited = HooksEdit.new(@record.hooks, JSON.parse(JSON.generate(settings))).call
        edited = StatusLineEdit.new(@record.status_line, edited).call
        PermissionsEdit.new(@record.permissions, edited).call
      end

      # Drops the listed [event, command] hook entries.
      class HooksEdit
        def initialize(entries, settings)
          @listed = entries.to_set { |entry| entry.values_at("event", "command") }
          @settings = settings
        end

        def call
          return @settings unless hooks.is_a?(Hash) && @listed.any?

          kept = hooks.to_h { |event, groups| [event, kept_groups(event, groups)] }.reject { |_event, groups| groups.empty? }
          SettingsEdit.put(@settings, "hooks", kept)
        end

        private

        def hooks = @settings["hooks"]

        def kept_groups(event, groups) = Array(groups).filter_map { |group| HookGroup.new(group).without(event, @listed) }
      end

      # One matcher group of hook entries; it goes when all its entries were listed.
      HookGroup = Data.define(:group) do
        def without(event, listed)
          return group unless entries.is_a?(Array)

          kept = entries.reject { |hook| hook.is_a?(Hash) && listed.include?([event, hook["command"]]) }
          group.merge("hooks" => kept) unless kept.empty? && entries.any?
        end

        private

        def entries = group.is_a?(Hash) && group["hooks"]
      end

      # Puts back the status line the install replaced, while Plastic's is still set.
      class StatusLineEdit
        def initialize(recorded, settings)
          @recorded = recorded
          @settings = settings
        end

        def call
          return @settings unless ours?

          replaced = @recorded["replaced"]
          replaced ? @settings.merge("statusLine" => replaced) : @settings.except("statusLine")
        end

        private

        def ours? = @recorded && current.is_a?(Hash) && current["command"] == @recorded["command"]

        def current = @settings["statusLine"]
      end

      # Drops the listed deny entries.
      class PermissionsEdit
        def initialize(entries, settings)
          @entries = entries
          @settings = settings
        end

        def call
          return @settings unless deny.is_a?(Array) && @entries.any?

          SettingsEdit.put(@settings, "permissions", SettingsEdit.put(permissions, "deny", deny - @entries))
        end

        private

        def permissions = @settings["permissions"].then { |rules| rules.is_a?(Hash) ? rules : {} }

        def deny = permissions["deny"]
      end
    end
  end
end
