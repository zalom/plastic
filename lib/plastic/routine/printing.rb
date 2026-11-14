# frozen_string_literal: true

require_relative "../failed"
require_relative "../finished"
require_relative "../handed_off"

module Plastic
  class Routine < CLI::Command
    # Prints the files a finished call wrote, for the kinds its class declares.
    module Printing
      private

      # Refuses a call that prints when a file it would print was changed by hand,
      # before any row is written.
      def hand_edit_failure(ctx)
        return if self.class.prints.empty? || parsed[:dry_run]

        facts = ctx.facts
        path = graphs.work.hand_edited(self.class.prints, intent_id: facts[:intent_id] || facts[:id], slug: facts[:slug]).first
        return unless path

        Failed.new(workflow: :print, step: "files", reason: Graph::Prints.hand_edit_line(path), next_command: "plastic sync up", because: "a file changed by hand is read into rows before a call prints it")
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
