# frozen_string_literal: true

module Plastic
  class CLI
    # Every command: its words, the class that runs it, and the one-line
    # summary `plastic help` prints. The class names its file: Commands::IntentEnd
    # is commands/intent_end.rb. `plastic help` reads this table alone, so
    # listing the commands loads no command. Each family owns its own section.
    TABLE = {
      # Storage
      "intent new" => ["Commands::IntentNew", "Open an intent: write its rows and print its folder"],
      "sync up" => ["Commands::SyncUp", "Read the files changed by hand into rows"],
      "sync down" => ["Commands::SyncDown", "Print the rows that changed into files"]
    }.freeze
  end
end
