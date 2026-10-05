# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"

module Plastic
  module Workflows
    # Reads the version history of the home. With a target version, names
    # the installer command that fetches that release; the reinstall that
    # follows syncs it into the home.
    class ShowRollback < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      MARK = { true => " (installed)" }.freeze
      RELEASES = "https://github.com/zalom/plastic/releases/download"

      sets :history, :current

      read "read the version history" do |context|
        installation = Installation.of(context)
        context[:history] = installation.ledger_read
        context[:current] = installation.installed_version
      end

      gate "%{target} is not in the version history", stops: :refusal,
        pass: ->(context) { context.target.nil? || context.history.any? { |entry| entry["version"] == context.target } }

      read "list the history or name the switch" do |context|
        context.target ? switch_lines(context) : history_lines(context)
      end

      outcome :switch, if: ->(context) { context.target }, offers: "plastic install --reinstall",
        because: "run the installer command above first"
      outcome :done, offers: "plastic rollback --version VERSION", because: "pick a version from the history"

      def self.switch_lines(context)
        target = context.target
        context.row("switch:", "#{context.current} to #{target}")
        context.row("run:", Installation.fetch_command("PLASTIC_ARCHIVE_URL=#{RELEASES}/v#{target}/plastic.tgz"))
      end

      def self.history_lines(context)
        history = context.history
        context.print("no version history yet; install or update first") if history.empty?
        history.each { |entry| context.row("history:", history_line(entry, context.current)) }
      end

      def self.history_line(entry, current)
        version = entry["version"]
        "#{version} #{entry["action"]} #{entry["at"]}#{MARK[version == current]}"
      end
    end
  end
end
