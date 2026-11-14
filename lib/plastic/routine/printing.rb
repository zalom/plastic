# frozen_string_literal: true

require_relative "../failed"
require_relative "../finished"
require_relative "../handed_off"
require_relative "hand_edit_refusal"

module Plastic
  class Routine < CLI::Command
    # Prints the files a finished call wrote, for the kinds its class declares.
    module Printing
      private

      # Refuses a call that prints when a file it would print was changed by hand,
      # before any row is written.
      def hand_edit_failure(ctx)
        kinds = self.class.prints
        return if kinds.empty? || parsed[:dry_run]

        path, reason = graphs.work.hand_edited(kinds, ctx.facts.merge(picked_facts(ctx))).first
        path && HandEditRefusal.call(path, reason)
      end

      # The facts a workflow picks before the call prints; a command whose files a workflow picks overrides this.
      def picked_facts(_ctx) = {}

      def walk(routine_run, ctx)
        Traversal.new(chain, ctx, routine_run) { |run| save_routine_run(run) }.call { |value| printing(value, ctx) }
      end

      def printing(value, ctx)
        print_files(ctx) if print_due?(value)
        value
      rescue => error
        Failed.raised(:print, "files", error)
      end

      def print_due?(value)
        [Finished, HandedOff].any? { |kind| value.is_a?(kind) } && self.class.prints.any? && graphs.wrote_rows?
      end

      def print_files(ctx)
        facts = ctx.facts
        self.class.prints.each do |kind|
          case kind
          when :intent then print_intent(facts[:intent_id])
          when :roadmap then print_roadmap(facts[:slug])
          else graphs.work.print_index
          end
        end
      end

      def print_intent(intent_id) = (graphs.work.print_intent(intent_id) if intent_id)

      def print_roadmap(slug) = (graphs.work.print_roadmap(slug) if slug)
    end
  end
end
