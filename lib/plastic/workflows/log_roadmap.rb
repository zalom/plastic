# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Appends one log line to a roadmap, stamped with the session id.
    class LogRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :line

      gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmap(context.slug).nil? }

      step "write the log line", done: ->(context) { !context.line.nil? } do |context|
        context[:line] = context.work.add_log(context.slug, context.text)
      end

      read "say what was logged" do |context|
        context.print("log: #{context.line.text}")
      end

      outcome :done, offers: "plastic roadmap show %{slug}", because: "the log line is on roadmap %{slug}"
    end
  end
end
