# frozen_string_literal: true

require_relative "../purge"
require_relative "../../../../code_workflow"

module Plastic
  module Workflows
    module Code
      class Backup
        class Purge
          # Lists the backups a purge would delete, and deletes nothing.
          class Preview < CodeWorkflow
            [facts, steps, outcomes].each(&:clear)

            read "preview the purge" do |context|
              next unless context.dry_run

              Code::Backup::Purge.targets(context).each { |name| context.print("preview: purge #{context.store}/#{name}") }
              context.print("preview: the original store was not changed")
            end

            outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}",
              because: "the preview deleted nothing"
            outcome :continue, offers: "plastic backup purge --store %{store}", because: "apply the requested purge"
          end
        end
      end
    end
  end
end
