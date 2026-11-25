# frozen_string_literal: true

require_relative "../errors"
require_relative "../finished"
require_relative "../handed_off"

module Plastic
  class Routine < CLI::Command
    # Prints the files a finished call wrote, for the kinds its class declares.
    module Printing
      module Facts
        # The facts a workflow adds to name the files to check; a command whose files a workflow picks overrides this.
        def hand_edit_additions(_ctx) = {}
      end

      private

      # Refuses a call that prints when a file it would print was changed by hand,
      # before any row is written.
      def refuse_hand_edits(ctx)
        klass = self.class
        kinds = klass.prints
        return if kinds.empty? || parsed[:dry_run]

        path, reason = graphs.work.hand_edited(kinds, ctx.facts.merge(klass.hand_edit_additions(ctx))).first
        path && refusal(path, reason)
      end

      # A file sync up reads is cleared by sync up; one it cannot read, by printing it again from its rows.
      def refusal(path, reason)
        return unreadable_refusal(path, reason) if reason

        raise Failed.new(Graph::Prints.hand_edit_line(path), next_command: "plastic store sync up", because: "a file changed by hand is read into rows before a call prints it", source: "print, files")
      end

      def unreadable_refusal(path, reason)
        raise Failed.new(Graph::Prints.unreadable_line(path, reason), next_command: "plastic store sync down --overwrite #{path}", because: "sync up cannot read the file, and its rows print it again", source: "print, files")
      end

      def walk(command_run, ctx)
        Traversal.new(chain, ctx, command_run) { |run| save_command_run(run) }.call { |value| printing(value, ctx) }
      end

      def printing(value, ctx)
        print_files(ctx) if print_due?(value)
        value
      rescue => error
        raise Failed.raised(:print, "files", error)
      end

      def print_due?(value)
        [Finished, HandedOff].any? { |kind| value.is_a?(kind) } && self.class.prints.any? && graphs.wrote_rows?
      end

      def print_files(ctx)
        facts = ctx.facts
        self.class.prints.each do |kind|
          case kind
          when :intent then print_intent(facts[:intent_id])
          else graphs.work.print_index
          end
        end
      end

      def print_intent(intent_id) = (graphs.work.print_intent(intent_id) if intent_id)
    end
  end
end
