# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../cli/screen"
require_relative "../installations"

module Plastic
  module Workflows
    # Reads the person's answer against the harnesses Plastic is installed
    # into or found in.
    class ChooseInstallations < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :found, :picked, :harnesses

      read "list the recorded and the found harnesses and read the person's answer" do |context|
        found = Installations.listed(context.scope)
        choices = found.map { |name| CLI::Screen::Choice.new(label: name, chosen: true) }
        result = CLI::Screen::Answer.new(choices).call(context.answer) if found.any?
        context[:found] = found
        context[:picked] = result.is_a?(CLI::Screen::Chosen) ? result.labels : []
        context[:harnesses] = context.picked.join(", ")
      end

      outcome :none, if: ->(context) { context.found.empty? }, offers: "plastic init",
        because: "Plastic is installed into no harness and no registered harness was found"
      outcome :left, if: ->(context) { context.picked.empty? }, offers: "plastic uninstall",
        because: "the person left with no change"
      outcome :chosen, offers: "plastic uninstall %{answer}", because: "remove Plastic from %{harnesses}"
    end
  end
end
