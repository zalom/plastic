# frozen_string_literal: true

module Plastic
  class CLI
    # Every command: its words, the class that runs it, and the one-line
    # summary `plastic help` prints. The class names its file: Commands::Intent::End
    # is commands/intent/end.rb. `plastic help` reads this table alone, so
    # listing the commands loads no command. Each family owns its own section.
    TABLE = {
      # Distribution
      "version" => ["Commands::Version", "Print the installed Plastic version and release channel"],
      "config" => ["Commands::Config", "Pick which on/off settings are on, on the choice screen"],
      "config list" => ["Commands::Config::List", "List every setting with its value, globally or for one harness"],
      "config get" => ["Commands::Config::Get", "Print the value of one setting"],
      "config set" => ["Commands::Config::Set", "Write one setting to config.yml, globally or for one harness"],
      "doctor" => ["Commands::Doctor", "Check the installation, the databases and the hooks of this harness, and name each repair"],
      "init" => ["Commands::Init", "Find the installed harnesses and install Plastic into the ones the person picks"],
      "install" => ["Commands::Install", "Install the core files and make the global store"],
      "update" => ["Commands::Update", "Sync a newer package into the home or name the installer command"],
      "rollback" => ["Commands::Rollback", "Switch the active release back to the previous one or to a named installed one"],
      "uninstall" => ["Commands::Uninstall", "Remove Plastic from agents and keep the home"],

      # Storage
      "intent abandon" => ["Commands::Intent::Abandon", "Close an intent that will not ship once outcome.md records the revert, or print the revert steps"],
      "intent end" => ["Commands::Intent::End", "Close a delivered intent once its verdict, nodes and outcome allow it, or print what is missing"],
      "intent new" => ["Commands::Intent::New", "Open an intent: write its rows and its folder"],
      "project list" => ["Commands::Project::List", "List the registered projects with their paths"],
      "project new" => ["Commands::Project::New", "Register a project and leave its store ready for intent new"],
      "project links" => ["Commands::Project::Links", "List the links that name an intent or a ruling this store lacks"],
      "sync up" => ["Commands::Sync::Up", "Read the files changed by hand into rows"],
      "sync down" => ["Commands::Sync::Down", "Write the rows that changed into files"],
      "session note" => ["Commands::Session::Note", "Write the one prose line of this session"],
      "intent rule" => ["Commands::Intent::Rule", "Write an owner ruling, with --supersedes to replace an older one"],
      "intent revise" => ["Commands::Intent::Revise", "Rewrite an intent's What and Why after grilling, keeping the old text as a revision"],
      "intent note" => ["Commands::Intent::Note", "Add one line under Notes in the outcome of an intent, keeping the earlier text as a revision"],
      "intent approve" => ["Commands::Intent::Approve", "Write the owner's go-ahead for an intent; auto refuses an intent without it"],
      "intent judge" => ["Commands::Intent::Judge", "Print the steps that start the judge of an intent"],
      "intent verdict" => ["Commands::Intent::Verdict", "Record the verdict of the next review round of an intent"],
      "intent spec" => ["Commands::Intent::Spec", "Print the grilling method, then the intent's open decisions"],
      "intent discover" => ["Commands::Intent::Discover", "Record deterministic retrieval candidates for an intent"],
      "intent context" => ["Commands::Intent::Context", "Read or submit selected retrieval context for an intent"],
      "architecture status" => ["Commands::Architecture::Status", "Tell the agent to check the architecture map with its own tool"],
      "architecture refresh" => ["Commands::Architecture::Refresh", "Tell the agent to regenerate the architecture map with its own tool"],
      "auto" => ["Commands::Auto", "Deliver one intent or one roadmap in auto mode: take the lock and print the worktree"],
      "intent lock status" => ["Commands::Intent::Lock::Status", "Print the session that holds an intent's lock, and its worktree"],
      "intent show" => ["Commands::Intent::Show", "Print one intent's status, criteria, decisions, rulings and nodes"],
      "intent brief" => ["Commands::Intent::Brief", "Print an intent's goal, criteria, rulings, ready nodes and command usage"],
      "status" => ["Commands::Status", "List every store's open and active intents, with node counts by state"],
      "next" => ["Commands::Next", "Pick the intent in play and offer its next command"],
      "intent link" => ["Commands::Intent::Link", "Write a typed link from an intent to a ref"],
      "intent unlink" => ["Commands::Intent::Unlink", "Remove a link"],
      "intent archive" => ["Commands::Intent::Archive", "Archive an intent directory"],
      "intent unarchive" => ["Commands::Intent::Unarchive", "Restore an archived intent's directory exactly as it was archived"],
      "backup" => ["Commands::Backup", "Copy one store's databases into a new backup folder"],
      "backup list" => ["Commands::Backup::List", "List one store's backups with status and goal, flagging a missing or changed file"],
      "backup purge" => ["Commands::Backup::Purge", "Delete one store's backups; give one of --all, --failed or --older-than"],
      "backup restore" => ["Commands::Backup::Restore", "Replace one store's databases with those of a done backup"],
      "document get" => ["Commands::Document::Get", "Fetch one current or revision-qualified document"],
      "document batch" => ["Commands::Document::Batch", "Fetch qualified documents in request order"],
      "search" => ["Commands::Search", "Search literal indexed passages across selected stores"],

      # Work graph
      "node add" => ["Commands::Node::Add", "Add a node to an intent's work graph"],
      "node remove" => ["Commands::Node::Remove", "Remove a node; its edges stay as rows"],
      "node claim" => ["Commands::Node::Claim", "Claim an open node and print its brief"],
      "node release" => ["Commands::Node::Release", "Release a claimed or failed node back to open"],
      "node done" => ["Commands::Node::Done", "Mark a claimed node done, with its findings as TEXT"],
      "node fail" => ["Commands::Node::Fail", "Mark a claimed node failed, with the reason as TEXT"],
      "node ask" => ["Commands::Node::Ask", "Move a claimed node to needs_info with a question for the owner"],
      "node impede" => ["Commands::Node::Impede", "Move a claimed node to impeded with the impediment"],
      "node resolve" => ["Commands::Node::Resolve", "Reopen a needs_info or impeded node with its resolution"],
      "edge add" => ["Commands::Edge::Add", "Add a needs edge between two nodes"],
      "edge remove" => ["Commands::Edge::Remove", "Remove an edge"],
      "graph check" => ["Commands::Graph::Check", "Find a done node with no findings, an isolated node, a retry cap or no done criterion"],
      "graph ready" => ["Commands::Graph::Ready", "List the nodes ready to claim"],
      "graph resume" => ["Commands::Graph::Resume", "Say where each named store's work stopped and what runs next"],
      "graph show" => ["Commands::Graph::Show", "Print every node and edge of an intent"],

      # Roadmaps: a named plan, held as rows instead of a hand-kept file.
      "roadmap new" => ["Commands::Roadmap::New", "Create a roadmap; write its batches with roadmap batch"],
      "roadmap batch" => ["Commands::Roadmap::Batch", "Write one roadmap batch's goal and done criteria"],
      "roadmap add" => ["Commands::Roadmap::Add", "Add an item to a roadmap batch, with the items it needs"],
      "roadmap show" => ["Commands::Roadmap::Show", "Print a roadmap's batches and items"],
      "roadmap next" => ["Commands::Roadmap::Next", "Print the first ready item, or what is in the way"],
      "roadmap drop" => ["Commands::Roadmap::Drop", "Mark a roadmap item dropped; its edges stay as rows"],
      "roadmap open" => ["Commands::Roadmap::Open", "Open a ready item's intent, with its spec held in rows"],
      "roadmap check" => ["Commands::Roadmap::Check", "List a roadmap's loops, dangling edges and items with no intent"],
      "roadmap log" => ["Commands::Roadmap::Log", "Append a log line to a roadmap, stamped with the session id"],
      "roadmap edge remove" => ["Commands::Roadmap::Edge::Remove", "Remove one needs edge from a roadmap"],

      # Hooks: the harness calls these on an event; see docs/contributing/ARCHITECTURE.md.
      "hook start" => ["Hooks::Start", "SessionStart: name the harness, open the session row, print the state the rows carry"],
      "hook stop" => ["Hooks::Stop", "Stop: stamp the turn, renew locks, run the stop gate"],
      "hook end" => ["Hooks::End", "SessionEnd: set the session's end time and reason"]
    }.freeze
  end
end
