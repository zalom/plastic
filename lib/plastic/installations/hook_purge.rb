# frozen_string_literal: true

require_relative "hook_registry"

module Plastic
  module Installations
    # Purges the hook entries the registry owns out of a hooks mapping, in
    # place, and returns [[event, command], ...] for each one it purged.
    # The predicate names the registry's rule for one harness.
    class HookPurge
      def initialize(predicate)
        @predicate = predicate
      end

      def call(hooks)
        removed = []
        hooks.each { |event, groups| hooks[event] = groups.filter_map { |group| keep(group, [event, removed]) } if groups.is_a?(Array) }
        removed
      end

      private

      def keep(group, purged)
        return group unless group.is_a?(Hash)

        list = group["hooks"]
        return nested(group, list, purged) if list.is_a?(Array)

        command = group["command"]
        command ? bare(group, command, purged) : group
      end

      def nested(group, list, purged)
        list.reject! { |hook| purge(hook["command"], purged) }
        group unless list.empty?
      end

      def bare(group, command, purged)
        group unless purge(command, purged)
      end

      def purge(command, (event, removed))
        owned?(command) && removed << [event, command]
      end

      def owned?(command) = HookRegistry.public_send(@predicate, command)
    end
  end
end
