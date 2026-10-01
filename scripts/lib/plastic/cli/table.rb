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
      "sync down" => ["Commands::SyncDown", "Print the rows that changed into files"],
      "session note" => ["Commands::SessionNote", "Write the one prose line of this session"],
      "intent rule" => ["Commands::IntentRule", "Write an owner ruling, with --supersedes to replace an older one"],
      "intent spec" => ["Commands::IntentSpec", "Print the grilling method, then the intent's open decisions"],
      "auto start" => ["Commands::AutoStart", "Take the delivery lock and set the intent active"],

      # Work graph
      "node add" => ["Commands::NodeAdd", "Add a node to an intent's work graph"],
      "node remove" => ["Commands::NodeRemove", "Remove a node; its edges stay as rows"],
      "node claim" => ["Commands::NodeClaim", "Claim an open node and print its brief"],
      "node release" => ["Commands::NodeRelease", "Release a claimed or failed node back to open"],
      "node done" => ["Commands::NodeDone", "Mark a claimed node done, with its judge and findings"],
      "node fail" => ["Commands::NodeFail", "Mark a claimed node failed, with a reason"],
      "node park" => ["Commands::NodePark", "Park a claimed node with a question for the owner"],
      "node answer" => ["Commands::NodeAnswer", "Answer a parked node and reopen it"],
      "edge add" => ["Commands::EdgeAdd", "Add a needs edge between two nodes"],
      "edge remove" => ["Commands::EdgeRemove", "Remove an edge"],

      # Hooks: the harness calls these on an event; see docs/contributing/ARCHITECTURE.md.
      "hook resume" => ["Hooks::Resume", "SessionStart: print the state the rows carry"],
      "hook record" => ["Hooks::Record", "Stop: stamp the turn, renew locks, run the stop gate"]
    }.freeze
  end
end
