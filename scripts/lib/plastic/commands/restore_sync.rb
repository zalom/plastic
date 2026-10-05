# frozen_string_literal: true

module Plastic
  module Commands
    # The question a restore puts to the person, and what each answer does.
    module RestoreSync
      DOWN = "down: prints the files from the restored rows. File edits made after the backup are lost."
      UP = "up: reads the files into the rows. Where a file is newer, it replaces the restored row."
      NEITHER = "neither: changes nothing; the rows and the files stay as they are."
      QUESTION = "sync the restored store?\n  #{DOWN}\n  #{UP}\n  #{NEITHER}\nanswer down, up or neither:"
      ANSWERS = %w[down up neither].freeze
      ASK_NEXT = "ask the person whether to sync the restored %{store} store up or down: #{DOWN} #{UP} " \
                 "Then run plastic sync down --project %{store} or plastic sync up --project %{store}; " \
                 "restore never syncs by itself".freeze

      module_function

      # A person at a terminal reads the lines before the question; otherwise they print with the answer.
      def say(context, line)
        dialog = context.scope.dialog
        dialog.terminal? ? dialog.output.raw(line) : context.print(line)
      end

      # What the person answered, "neither" when no answer is a choice, or "none" with no person.
      def answer(context)
        dialog = context.scope.dialog
        return "none" unless dialog.terminal?

        dialog.choose(QUESTION, choices: ANSWERS) || "neither"
      end

      def chosen(name) = ->(context) { context.sync_choice == name }
    end
  end
end
