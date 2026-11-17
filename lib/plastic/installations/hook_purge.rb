# frozen_string_literal: true

require_relative "hook_registry"

module Plastic
  module Installations
    # Purges the hook entries the registry owns out of a hooks mapping, in
    # place, and returns [[event, command], ...] for each one it purged.
    # The predicate names the registry's rule for one harness.
    class HookPurge
      # One group of an event: a mapping with a list of hooks, or a bare hook.
      Group = Data.define(:entry) do
        # Returns [the group to keep or nil, the commands purged out of it].

        def purge(owned)
          fields = entry.is_a?(Hash) ? entry : {}
          list = fields["hooks"]
          return purge_list(list, owned) if list.is_a?(Array)

          command = fields["command"]
          (command && owned.call(command)) ? [nil, [command]] : [entry, []]
        end

        private

        def purge_list(list, owned)
          removed = list.select { |hook| owned.call(hook["command"]) }
          list.replace(list - removed)
          [(entry unless list.empty?), removed.map { |hook| hook.fetch("command") }]
        end
      end

      def initialize(predicate)
        @predicate = predicate
      end

      def call(hooks) = hooks.flat_map { |event, groups| groups.is_a?(Array) ? purge_event(hooks, event, groups) : [] }

      private

      def purge_event(hooks, event, groups)
        purged = groups.map { |group| Group.new(group).purge(method(:owned?)) }
        hooks[event] = purged.filter_map(&:first)
        purged.flat_map(&:last).map { |command| [event, command] }
      end

      def owned?(command) = HookRegistry.public_send(@predicate, command)
    end
  end
end
