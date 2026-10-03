# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"
require_relative "release_update"

module Plastic
  module Workflows
    # Compares the installed version with the running package. A dry run
    # names both and what the update would do.
    class PreviewUpdate < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :from, :to

      gate "choose one channel: --stable, --beta or --alpha", stops: :refusal,
        pass: ->(context) { ReleaseUpdate.chosen_channels(context).size <= 1 }

      read "compare the installed and the running versions" do |context|
        installation = Installation.of(context)
        context[:from] = installation.installed_version
        context[:to] = installation.version
      end

      gate "Plastic is not installed under this home; run plastic install first", stops: :refusal,
        pass: ->(context) { !context.from.nil? }

      read "say what the update would do" do |context|
        if context.dry_run
          context.row("from:", context.from)
          context.row("to:", context.to)
        end
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "plastic update", because: "the preview changed no file"
      outcome :continue, offers: "plastic update", because: "update the home"
    end
  end
end
