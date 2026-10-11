# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../cli/screen"
require_relative "../harnesses"

module Plastic
  module Workflows
    # Reads the person's answer against the installed harnesses, every one
    # of them picked at the start.
    class ChooseHarnesses < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :found, :picked, :harnesses

      read "find the installed harnesses and read the person's answer" do |context|
        found = Harnesses.found_in(context.scope).map(&:name)
        choices = found.map { |name| CLI::Screen::Choice.new(label: name, chosen: true) }
        result = CLI::Screen::Answer.new(choices).call(context.answer) if found.any?
        context[:found] = found
        context[:picked] = result.is_a?(CLI::Screen::Chosen) ? result.labels : []
        context[:harnesses] = context.picked.join(", ")
      end

      outcome :none, if: ->(context) { context.found.empty? }, offers: "plastic init",
        because: "no registered harness was found: no settings folder in the home and no program on the PATH; install one, then run this again"
      outcome :left, if: ->(context) { context.picked.empty? }, offers: "plastic init",
        because: "the person left with no change"
      outcome :chosen, offers: "plastic init %{answer}", because: "install Plastic into %{harnesses}"
    end
  end
end
