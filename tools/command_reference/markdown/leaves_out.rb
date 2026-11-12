# frozen_string_literal: true

module CommandReference
  module Markdown
    # What the page leaves out: what every call shares, exit 3 when no gate refuses, and the routine run a stop saves.
    class LeavesOut
      SHARED = "../../dsl/README.md#what-every-call-shares"
      NO_REFUSAL = "No gate of this command refuses, so exit 3 never happens."
      ROUTINE_RUN = "A call that writes saves a routine run row in local.db. A stop by a gate or a step saves the run, and the next call resumes from it. A dry run saves no row."

      def initialize(page)
        @page = page
      end

      def lines = ["## What the page leaves out", "", "Every call shares a few things that this page does not repeat; [the command DSL](#{SHARED}) names them.", "", *notes]

      private

      def notes = [*refusal, *run].map { |text| "- #{text}" }.then { |items| items.empty? ? [] : [*items, ""] }

      def refusal = (NO_REFUSAL if @page.endings.none? { |ending| ending.exit_code == 3 } && @page.options.none? { |option| option.switch.start_with?("--dry-run") })

      def run = (ROUTINE_RUN if @page.kind == :routine && @page.klass.writes.any?)
    end
  end
end
