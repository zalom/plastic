# frozen_string_literal: true

# Plastic::CLI::TABLE (intent 363) - the whole command line in one frozen hash:
# a command name mapped to the file that holds it, the class inside
# Plastic::CLI::Commands, and the one line `plastic help` prints beside it.
#
# Adding a command is one row here plus one file. `plastic help` reads this
# hash and loads nothing, so listing the commands costs no command file.
# test/cli/table_test.rb walks every row, so a half-wired command cannot ship.
module Plastic
  class CLI
    TABLE = {
      "continue" => ["commands/continue", "Continue", "Show where one project stands and what runs next"],
      "doctor" => ["commands/doctor", "Doctor", "Diagnose Plastic installation health"],
      "feedback" => ["commands/feedback", "Feedback", "File a feedback report, body on standard input"],
      "help" => ["commands/help", "Help", "List the commands and help topics, or show one usage"],
      "install" => ["commands/install", "Install", "Install Plastic into this machine's agents"],
      "intent" => ["commands/intent", "Intent", "List the intent subcommands"],
      "intent answer" => ["commands/intent_answer", "IntentAnswer", "Answer an intent's needs_decision node"],
      "intent end" => ["commands/intent_end", "IntentEnd", "Close an intent as delivered or abandoned"],
      "intent new" => ["commands/intent_new", "IntentNew", "Create a new intent"],
      "intent note" => ["commands/intent_note", "IntentNote", "Append a savepoint note to an intent"],
      "intent rule" => ["commands/intent_rule", "IntentRule", "Record a ruling in an intent's Insights"],
      "intent show" => ["commands/intent_show", "IntentShow", "Print an intent's state screen"],
      "intent spec" => ["commands/intent_spec", "IntentSpec", "Print an intent's state screen, then the speccing rules"],
      "intent step" => ["commands/intent_step", "IntentStep", "Run the next ready step of an intent's graph"],
      "intent verify" => ["commands/intent_verify", "IntentVerify", "Run an intent's merge-gate checks"],
      "next" => ["commands/next", "Next", "Print the next action in one line"],
      "rollback" => ["commands/rollback", "Rollback", "Move to a Plastic version this machine has run before"],
      "status" => ["commands/status", "Status", "Show active work in every store"],
      "uninstall" => ["commands/uninstall", "Uninstall", "Remove Plastic from this machine's agents"],
      "update" => ["commands/update", "Update", "Move Plastic to the next version on its channel"],
      "version" => ["commands/version", "Version", "Print the installed Plastic version"]
    }.freeze
  end
end
