# frozen_string_literal: true

require_relative "../failed"
require_relative "../finished"
require_relative "../handed_off"

module Plastic
  class Routine < CLI::Command
    # `prints :intent` in a routine's class body prints the files of the intent
    # the call worked on after the chain, from the rows it wrote. `prints :roadmap`
    # prints the roadmap file, and `prints :index` prints store/index.json. A
    # call that ends Failed or Refused, or wrote no row but its routine run,
    # prints nothing.
    module Printing
      private

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
        self.class.prints.each do |kind|
          case kind
          when :intent then print_intent(ctx.facts[:intent_id])
          when :roadmap then print_roadmap(ctx.facts[:slug])
          else graphs.work.print_index
          end
        end
      end

      def print_intent(intent_id) = (graphs.work.print_intent(intent_id) if intent_id)

      def print_roadmap(slug) = (graphs.work.print_roadmap(slug) if slug)
    end
  end
end
