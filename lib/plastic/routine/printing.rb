# frozen_string_literal: true

require_relative "../failed"
require_relative "../finished"
require_relative "../handed_off"

module Plastic
  class Routine < CLI::Command
    # Prints the files a finished call wrote, for the kinds its class declares.
    module Printing
      # A file sync up reads is cleared by sync up; one it cannot read, by printing it again from its rows.
      def self.refusal(path, reason) = reason ? unreadable_refusal(path, reason) : changed_refusal(path)

      def self.changed_refusal(path)
        Failed.new(workflow: :print, step: "files", reason: Graph::Prints.hand_edit_line(path), next_command: "plastic sync up", because: "a file changed by hand is read into rows before a call prints it")
      end

      def self.unreadable_refusal(path, reason)
        Failed.new(workflow: :print, step: "files", reason: Graph::Prints.unreadable_line(path, reason), next_command: "plastic sync down --overwrite #{path}", because: "sync up cannot read the file, and its rows print it again")
      end

      private

      # Refuses a call that prints when a file it would print was changed by hand,
      # before any row is written.
      def hand_edit_failure(ctx)
        kinds = self.class.prints
        return if kinds.empty? || parsed[:dry_run]

        path, reason = graphs.work.hand_edited(kinds, ctx.facts.merge(picked_facts(ctx))).first
        path && Printing.refusal(path, reason)
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
