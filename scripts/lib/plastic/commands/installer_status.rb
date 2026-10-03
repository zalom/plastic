# frozen_string_literal: true

require_relative "../../installer_release"
require_relative "../cli/command"

module Plastic
  module Commands
    # The installer commands share a read-only planning boundary. A later
    # workflow may apply a plan only after it has a verified manifest and
    # archive. Keeping that gate here makes an accidental write impossible
    # while the release-fetch path is still unfinished.
    class InstallerStatus < CLI::Command
      option :dry_run, switch: "--dry-run", default: false, text: "print the verified release plan without writing files"

      def call
        return preview if parsed[:dry_run]

        raise CLI::Command::Refusal, "a verified release manifest is required before #{words} can write files"
      end

      private

      def preview
        plan = installer_plan.preview(words)
        output.row("preview:", plan.fetch(:verb))
        output.row("version:", plan.fetch(:version))
        output.row("channel:", plan.fetch(:channel))
        output.row("writes:", "none")
        output.next_step("plastic #{words}", because: plan.fetch(:message))
      end

      def installer_plan
        InstallerRelease::Plan.new(home: installer_home, package_root: package_root)
      end

      def installer_home = environment.env["PLASTIC_HOME"] || File.join(environment.home, ".plastic")

      def package_root = environment.env.fetch("PLASTIC_PACKAGE_ROOT", ENV.fetch("PLASTIC_PACKAGE_ROOT", Dir.pwd))
    end
  end
end
