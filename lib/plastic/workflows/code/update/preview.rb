# frozen_string_literal: true

require_relative "../update"
require_relative "../../../code_workflow"
require_relative "../../installation"
require_relative "../../release_update"

module Plastic
  module Workflows
    module Code
      class Update
        # Compares the installed version, or the release install.sh activated
        # when no harness is set up yet, with the version a real run would
        # install. A dry run names both; to find the second it asks the release
        # source, as the real run does, and prints the source notices. A real
        # run asks nothing here.
        class Preview < CodeWorkflow
          clear_declarations
          summary "Shows what an update would do before anything is changed."

          sets :from, :to

          read "compare the installed version with the one a real run would install" do |context|
            installation = Installation.of(context)
            context[:from] = installation.installed_version || ReleaseUpdate.of(context).active_version
            context[:to] = context.dry_run ? target(context, installation) : installation.version
          end

          gate "Plastic is not installed under this home; run plastic install first", stops: :refusal,
            pass: ->(context) { !context.from.nil? }

          read "say what the update would do" do |context|
            if context.dry_run
              context.row("from:", context.from)
              context.row("to:", context.to)
            end
          end

          outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}", because: "the preview changed no file"
          outcome :continue, offers: "plastic update", because: "update the home"

          # What a real run installs: the running package when it is newer than
          # the installed one, else the newest release on the channel, else the
          # version already there.
          def self.target(context, installation)
            return installation.version if installation.installed? && installation.newer?

            release = ReleaseUpdate.of(context)
            (release.active_version && newest(context, release)) || context.from
          end

          def self.newest(context, release)
            release.notices.each { |notice| context.print(notice) }
            release.newer_release(context.channel)
          end
        end
      end
    end
  end
end
