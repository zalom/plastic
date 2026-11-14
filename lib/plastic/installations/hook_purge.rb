# frozen_string_literal: true

require_relative "hook_registry"

module Plastic
  module Installations
    # Takes the hook entries the registry owns out of a hooks mapping, in
    # place, and returns [[event, command], ...] for each one it took out.
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

      def keep(group, taken)
        return group unless group.is_a?(Hash)

        list = group["hooks"]
        return nested(group, list, taken) if list.is_a?(Array)

        command = group["command"]
        command ? bare(group, command, taken) : group
      end

      def nested(group, list, taken)
        list.reject! { |hook| take(hook["command"], taken) }
        group unless list.empty?
      end

      def bare(group, command, taken)
        group unless take(command, taken)
      end

      def take(command, (event, removed))
        owned?(command) && removed << [event, command]
      end

      def owned?(command) = HookRegistry.public_send(@predicate, command)
    end
  end
end
