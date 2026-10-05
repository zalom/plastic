# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"

module Plastic
  module Workflows
    # On a dry run, lists each core file the install would add or replace.
    class PreviewInstall < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      read "list the core files the install would write" do |context|
        if context.dry_run
          installation = Installation.of(context)
          context.row("preview:", "install #{installation.version} into #{installation.plastic_home}")
          installation.planned_files.each { |(change, path)| context.row("#{change}:", path) }
        end
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "plastic install",
        because: "the preview changed no file"
      outcome :continue, offers: "plastic install", because: "install the core files"
    end
  end
end
