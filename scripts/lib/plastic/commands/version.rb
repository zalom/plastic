# frozen_string_literal: true

require_relative "installer_status"

module Plastic
  module Commands
    # Prints the active release when one exists, otherwise the shipped one.
    class Version < InstallerStatus
      def call
        plan = installer_plan
        output.row("version:", plan.installed_version)
        output.row("channel:", plan.channel)
        output.next_step("plastic install --dry-run", because: "review the verified installation plan")
      end
    end
  end
end
