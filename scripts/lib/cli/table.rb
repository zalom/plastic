# encoding: UTF-8
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
      "help" => ["commands/help", "Help", "List the commands, or show one command's usage"],
      "install" => ["commands/install", "Install", "Install Plastic into this machine's agents"],
      "next" => ["commands/next", "Next", "Print the next action in one line"],
      "rollback" => ["commands/rollback", "Rollback", "Move to a Plastic version this machine has run before"],
      "status" => ["commands/status", "Status", "Show active work in every store"],
      "uninstall" => ["commands/uninstall", "Uninstall", "Remove Plastic from this machine's agents"],
      "update" => ["commands/update", "Update", "Move Plastic to the next version on its channel"],
      "version" => ["commands/version", "Version", "Print the installed Plastic version"]
    }.freeze
  end
end
