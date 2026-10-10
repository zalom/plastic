# frozen_string_literal: true

module CommandReference
  module Dsl
    # How a call ends: the four values, then every ending that holds for any command.
    class EndingsSection < Section
      KERNEL = [
        ["a wrong argument or option", 2, "prints the usage line", :command, /def settle\b/],
        ["`--help`", 0, "prints the help", :command, /def help\b/],
        ["a missing store", 1, "the command that creates the store", :command, /when Graph::MissingStore/],
        ["a broken projects file", 1, "prints no next: line", :command, /def broken\b/]
      ].freeze
      OTHER = [
        ["a step whose done check still fails", 1, "prints no next: line", "scripts/lib/plastic/code_workflow/step.rb", /still fails/],
        ["a step that raises, except a usage error, which keeps exit 2", 1, "prints no next: line", "scripts/lib/plastic/code_workflow.rb", /Failed\.raised\(key, step\.name/],
        ["a print failure after the chain", 1, "prints no next: line", "scripts/lib/plastic/routine/printing.rb", /Failed\.raised\(:print/],
        ["a closing line that cannot fill", 1, "prints no next: line", "scripts/lib/plastic/finished.rb", /Failed\.raised\(workflow\.key, "closing"/],
        ["an agent handoff that cannot print", 1, "prints no next: line", "scripts/lib/plastic/agent_workflow.rb", /Failed\.raised\(key, "handoff"/],
        ["a dry run that cannot open its database", 1, "prints no next: line", "scripts/lib/plastic/routine/preview.rb", /rescue Graph::Database::Error/],
        ["a dry run that cannot copy the store", 3, "prints no next: line", "scripts/lib/plastic/routine/preview.rb", /rescue Graph::DisposableCopy::Refused/]
      ].freeze

      def lines
        [*opening("How a call ends", "endings.svg", "The four ways a plastic call ends, each with its exit code"),
          "No workflow picks an exit code. A call ends in one of these four values, and the value prints the last lines and gives the code.", "",
          "| Value | Exit | Defined in |", "| --- | --- | --- |",
          *@dsl.ends.map { |value| "| `#{value.fetch(:name)}` | #{value.fetch(:exit_code)} | #{@links.code(value.fetch(:file), value.fetch(:line))} |" }, "",
          "## How any call can end", "",
          "These endings hold for every command, so a command page lists only its own.", "",
          "| Ending | Exit | next: | Code |", "| --- | --- | --- | --- |", *rows, ""]
      end

      private

      def rows = KERNEL.map { |ending| row(ending[0], ending[1], ending[2], DslPage::FILES.fetch(ending[3]), ending[4]) } + OTHER.map { |ending| row(*ending) }

      def row(words, code, next_text, file, pattern) = "| #{words} | #{code} | #{next_text} | #{@links.code(file, @dsl.source.find_line(file, pattern))} |"
    end

    # The files that define the DSL.
    class FilesSection < Section
      ROWS = {
        routine: "the command class and `workflow`", declarations: "`intent_subject`, `argument`, `option`, `reads` and `writes`",
        branches: "`on`", chain: "the chain and its wiring checks", workflow: "what both kinds of workflow share: `sets` and `outcome`",
        code: "`read`, `gate`, `step` and `forget_stop`", agent: "the agent `step` and its handoff", finished: "the four end values"
      }.freeze

      def lines
        ["---", "", "## Where the DSL lives", "", "| File | What it defines |", "| --- | --- |",
          *ROWS.map { |key, words| "| #{@links.file(DslPage::FILES.fetch(key))} | #{words} |" }, ""]
      end
    end
  end
end
