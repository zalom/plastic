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
        hooks.each_with_object([]) do |(event, groups), removed|
          hooks[event] = groups.filter_map { |group| keep(group, event, removed) } if groups.is_a?(Array)
        end
      end

      private

      def keep(group, event, removed)
        return group unless group.is_a?(Hash)
        return nested(group, event, removed) if group["hooks"].is_a?(Array)

        group["command"] ? bare(group, event, removed) : group
      end

      def nested(group, event, removed)
        group["hooks"].reject! { |hook| owned?(hook["command"]) && removed << [event, hook["command"]] }
        group unless group["hooks"].empty?
      end

      def bare(group, event, removed)
        return group unless owned?(group["command"])

        removed << [event, group["command"]]
        nil
      end

      def owned?(command) = HookRegistry.public_send(@predicate, command)
    end
  end
end
