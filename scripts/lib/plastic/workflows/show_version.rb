# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"

module Plastic
  module Workflows
    # Reads the version of the running package: its VERSION file when it has
    # one, as an installed copy does, otherwise its package.json.
    class ShowVersion < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :source

      read "find the version file of the running package" do |context|
        context[:source] = Installation.source(Installation.package_root(context.scope))
      end

      gate "the running package has no VERSION file and no package.json", stops: :failure,
        pass: ->(context) { !context.source.nil? }

      read "say the version and its channel" do |context|
        installation = Installation.of(context)
        context.row("version:", installation.version)
        context.row("channel:", installation.channel)
        context.row("source:", context.source)
      end

      outcome :done, offers: "plastic status", because: "the command line works, so read the work next"
    end
  end
end
