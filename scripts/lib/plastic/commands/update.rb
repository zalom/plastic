# frozen_string_literal: true

require_relative "../routine"
require_relative "../workflows/release_update"

module Plastic
  module Commands
    # Syncs a newer running package into the home, or activates the newest
    # release of the chosen channel, by default the active release's own.
    class Update < Routine
      opens_no_store

      option :channel, switch: "--channel NAME", text: "update from this channel: stable, beta or alpha"
      option :dry_run, switch: "--dry-run", default: false, text: "name both versions and change nothing"

      def call
        channel = parsed[:channel]
        raise CLI::Command::Usage, "--channel takes stable, beta or alpha" unless [nil, *Workflows::ReleaseUpdate::CHANNELS.keys].include?(channel)

        super
      end

      workflow :code_preview_update do
        on :done, next: :noop
        on :continue, next: :code_update_plastic
      end
      workflow :code_update_plastic, next: :noop
    end
  end
end
