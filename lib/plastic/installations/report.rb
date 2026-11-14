# frozen_string_literal: true

require_relative "hook_registry"

module Plastic
  module Installations
    # The plain lines an install prints about the settings it changed.
    module Report
      module_function

      def tilde(path) = path.to_s.sub(Dir.home, "~")

      # [[event, command], ...] for every hook command in a hooks mapping.
      def pairs(hooks)
        hooks.flat_map { |event, groups| paired(event, groups) }
      end

      def paired(event, groups) = commands(groups).map { |command| [event, command] }

      def commands(groups) = Array(groups).flat_map { |group| Array(group["hooks"]) }.map { |hook| hook["command"] }

      def removed_hooks(removed, label)
        count = removed.size
        return if count.zero?

        puts "  Removed #{count} stale Plastic hook entr#{(count == 1) ? "y" : "ies"} from #{label}:"
        removed.each { |event, command| puts "     - #{event}: #{tilde(command)}" }
      end

      # A hook the purge kept because the registry does not know it, whose
      # name carries the reserved plastic- prefix. The update says so, so the
      # person learns the prefix is reserved before a later update mistakes it.
      def reserved_hooks(hooks)
        kept = kept_names(hooks)
        return if kept.empty?

        puts "  Kept #{kept.size} hook(s) Plastic does not own, named with the reserved plastic- prefix:"
        kept.each { |command| puts "     - #{tilde(command)}" }
        puts "     The plastic- prefix is reserved for Plastic's own hooks. Rename yours (for"
        puts "     example ~/.claude/hooks/plain-writing) so a future update never mistakes it."
      end

      def kept_names(hooks)
        groups = hooks.values.grep(Array).flat_map { |list| list.grep(Hash) }
        groups.flat_map { |group| named(group) }.compact.select { |command| own_name?(command) }.uniq
      end

      def own_name?(command) = HookRegistry.command_basenames(command).any? { |name| name.start_with?("plastic-") }

      def named(group) = Array(group["hooks"]).map { |hook| hook["command"] } + [group["command"]]
    end
  end
end
