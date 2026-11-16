# frozen_string_literal: true

require_relative "../../routine"
require_relative "../../graph/backup/older_than"

module Plastic
  module Commands
    module Intent
      # Takes a done, abandoned or future intent off the checkout, or each one older than a date; its rows stay.
      class Archive < Routine
        def self.usage_line(tool = tool_name) = super.sub("[ID] [--older-than DATE]", "(ID | --older-than DATE)")

        subject :intent_id
        argument :intent_id, label: "ID", text: "the intent to archive", optional: true
        option :older_than, switch: "--older-than DATE", text: "archive every intent older than this date or time instead of one"
        writes :work, :knowledge, :references
        prints :index
        previews
        backs_up_first

        workflow :code_archive_intent, next: :noop

        def call
          check_choice
          super
        end

        private

        def check_choice
          given = [parsed[:intent_id], parsed[:older_than]].count { |value| value }
          raise CLI::Command::Usage, "give an intent ID or --older-than DATE" if given.zero?
          raise CLI::Command::Usage, "an intent ID and --older-than exclude each other" if given > 1

          read_date
        end

        def read_date
          Plastic::Graph::Backup::OlderThan.parse(parsed[:older_than]) if parsed[:older_than]
        rescue Plastic::Graph::Backup::OlderThan::Unreadable => error
          raise CLI::Command::Usage, error.message
        end
      end
    end
  end
end
