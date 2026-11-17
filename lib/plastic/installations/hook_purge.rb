# frozen_string_literal: true

require_relative "hook_registry"

module Plastic
  module Installations
    # Purges the hook entries the registry owns out of a hooks mapping, in
    # place, and returns [[event, command], ...] for each one it purged.
    # The predicate names the registry's rule for one harness.
    class HookPurge
      # A list of hooks. It drops the hooks the rule owns, in place, and says which commands it dropped.
      HookList = Data.define(:items) do
        def purge(owned)
          removed = items.select { |hook| owned.call(hook["command"]) }
          items.replace(items - removed)
          removed.map { |hook| hook.fetch("command") }
        end

        def keep(entry, owned)
          removed = purge(owned)
          [(entry unless items.empty?), removed]
        end
      end

      # One group of an event: a mapping with a list of hooks, or a bare hook.
      # Returns [the group to keep or nil, the commands purged out of it].
      Group = Data.define(:entry) do
        def purge(owned)
          fields = entry.is_a?(Hash) ? entry : {}
          list = fields["hooks"]
          return HookList.new(list).keep(entry, owned) if list.is_a?(Array)

          command = fields["command"]
          (command && owned.call(command)) ? [nil, [command]] : [entry, []]
        end
      end

      # The groups of one event in a hooks mapping. It writes the kept groups back and returns [event, command] pairs.
      Event = Data.define(:hooks, :name) do
        def purge(owned)
          purged = hooks[name].map { |entry| Group.new(entry).purge(owned) }
          hooks[name] = purged.filter_map(&:first)
          purged.flat_map(&:last).map { |command| [name, command] }
        end

        def groups? = hooks[name].is_a?(Array)
      end

      def initialize(predicate)
        @predicate = predicate
      end

      def call(hooks)
        events = hooks.keys.map { |name| Event.new(hooks, name) }
        events.select(&:groups?).flat_map { |event| event.purge(method(:owned?)) }
      end

      private

      def owned?(command) = HookRegistry.public_send(@predicate, command)
    end
  end
end
