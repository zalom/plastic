# frozen_string_literal: true

module Plastic
  class CLI
    # Every command: its words, the class that runs it, and the one-line
    # summary `plastic help` prints. The class names its file: Commands::IntentEnd
    # is commands/intent_end.rb. `plastic help` reads this table alone, so
    # listing the commands loads no command. Each family owns its own section.
    TABLE = {
      # Storage
      "intent end" => ["Commands::IntentEnd", "Record explicit criterion acceptance and close a delivered intent"],
      "intent new" => ["Commands::IntentNew", "Open an intent: write its rows and print its folder"],
      "sync up" => ["Commands::SyncUp", "Read the files changed by hand into rows"],
      "sync down" => ["Commands::SyncDown", "Print the rows that changed into files"],
      "session note" => ["Commands::SessionNote", "Write the one prose line of this session"],
      "intent rule" => ["Commands::IntentRule", "Write an owner ruling, with --supersedes to replace an older one"],
      "intent spec" => ["Commands::IntentSpec", "Print the grilling method, then the intent's open decisions"],
      "intent discover" => ["Commands::IntentDiscover", "Record deterministic retrieval candidates for an intent"],
      "auto start" => ["Commands::AutoStart", "Take the delivery lock and set the intent active"],
      "intent show" => ["Commands::IntentShow", "Print one intent's status, criteria, decisions, rulings and nodes"],
      "intent brief" => ["Commands::IntentBrief", "Print an intent's goal, criteria, rulings, ready nodes and command usage"],
      "status" => ["Commands::Status", "List every store's open and active intents, with node counts by state"],
      "next" => ["Commands::Next", "Pick the intent in play and offer its next command"],
      "intent link" => ["Commands::IntentLink", "Write a typed link from an intent to a ref"],
      "intent unlink" => ["Commands::IntentUnlink", "Remove a link"],
      "intent archive" => ["Commands::IntentArchive", "Archive an intent directory; --revert restores it"],
      "backup" => ["Commands::Backup", "Pack home.db and every store's three databases into one archive"],
      "backup list" => ["Commands::BackupList", "List every backup, flagging a missing or changed file"],
      "document get" => ["Commands::DocumentGet", "Fetch one current or revision-qualified document"],
      "document batch" => ["Commands::DocumentBatch", "Fetch qualified documents in request order"],
      "search" => ["Commands::Search", "Search literal indexed passages across selected stores"],

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
      "graph check" => ["Commands::GraphCheck", "Find a judge missing, an isolated node, a retry cap or no done criterion"],
      "graph ready" => ["Commands::GraphReady", "List the nodes ready to claim"],
      "graph show" => ["Commands::GraphShow", "Print every node and edge, then reprint graph.json from rows"],

      # Roadmaps: a named plan, held as rows instead of a hand-kept file.
      "roadmap batch" => ["Commands::RoadmapBatch", "Write one roadmap batch's goal and done criteria"],
      "roadmap add" => ["Commands::RoadmapAdd", "Add an item to a roadmap batch, after whichever items it waits on"],
      "roadmap show" => ["Commands::RoadmapShow", "Print a roadmap's batches and items, then reprint its file"],
      "roadmap next" => ["Commands::RoadmapNext", "Print the first ready item, or what is in the way"],
      "roadmap drop" => ["Commands::RoadmapDrop", "Mark a roadmap item dropped; its edges stay as rows"],
      "roadmap start" => ["Commands::RoadmapStart", "Open a ready item's intent, with its spec held in rows"],
      "roadmap check" => ["Commands::RoadmapCheck", "List a roadmap's loops, dangling edges and items with no intent"],
      "roadmap log" => ["Commands::RoadmapLog", "Append a log line to a roadmap, stamped with the session id"],
      "roadmap edge remove" => ["Commands::RoadmapEdgeRemove", "Remove one after edge from a roadmap"],

      # Hooks: the harness calls these on an event; see docs/contributing/ARCHITECTURE.md.
      "hook resume" => ["Hooks::Resume", "SessionStart: print the state the rows carry"],
      "hook record" => ["Hooks::Record", "Stop: stamp the turn, renew locks, run the stop gate"]
    }.freeze
  end
end
