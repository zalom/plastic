# frozen_string_literal: true

require_relative "table/work_families"

module Plastic
  class CLI
    # Every command: its words, the class that runs it, and the one-line
    # summary `plastic help` prints, grouped in families. Core holds the commands
    # that name no family; every other family holds the commands that start with
    # its word. The class names its file: Commands::Intent::End is
    # commands/intent/end.rb. `plastic help` reads this table alone, so listing
    # the commands loads no command.
    FAMILIES = {
      "core" => {
        "version" => ["Commands::Version", "Print the installed Plastic version and release channel"],
        "doctor" => ["Commands::Doctor", "Check the installation, the databases, the hooks of this harness and the folder layout of each store, rebuild a search index that is out of step, and name each repair"],
        "init" => ["Commands::Init", "Find the installed harnesses and install Plastic into the ones the person picks"],
        "install" => ["Commands::Install", "Install the core files and make the global store"],
        "update" => ["Commands::Update", "Sync a newer package into the home or name the installer command"],
        "rollback" => ["Commands::Rollback", "Switch the active release back to the previous one or to a named installed one"],
        "uninstall" => ["Commands::Uninstall", "Remove Plastic from agents and keep the home"],
        "status" => ["Commands::Status", "List every store's intents by group, with node counts by state"],
        "next" => ["Commands::Next", "Pick the intent in play and offer its next command"],
        "search" => ["Commands::Search", "Search indexed passages across selected stores for the words of a question, best match first"],
        "console" => ["Commands::Console", "Open IRB over the store databases read-only, or run one piece of Ruby with --eval and print its value"]
      },
      "intent" => {
        "intent abandon" => ["Commands::Intent::Abandon", "Close an intent that will not ship once outcome.md records the revert, or print the revert steps"],
        "intent end" => ["Commands::Intent::End", "Close a delivered intent once its verdict, nodes and outcome allow it, or print what is missing"],
        "intent new" => ["Commands::Intent::New", "Write a future intent: its rows and its folder"],
        "intent start" => ["Commands::Intent::Start", "Start an intent for guided work: set it in progress and print its worktree"],
        "intent auto" => ["Commands::Intent::Auto", "Start an intent for agent delivery: set it in progress and print its worktree"],
        "intent park" => ["Commands::Intent::Park", "Park an intent in progress with the reason it waits; intent start resumes it"],
        "intent rule" => ["Commands::Intent::Rule", "Write an owner ruling, with --supersedes to replace an older one"],
        "intent revise" => ["Commands::Intent::Revise", "Rewrite an intent's What and Why after grilling, keeping the old text as a revision"],
        "intent note" => ["Commands::Intent::Note", "Add one line to the outcome of an intent, a note under Notes or a record of the delivery or the close under Verification, keeping the earlier text as a revision"],
        "intent outcome" => ["Commands::Intent::Outcome", "Write the summary of the outcome of an intent from a file, keeping its title and every section"],
        "intent report" => ["Commands::Intent::Report", "Record a report of an intent so the sync reads it"],
        "intent unreport" => ["Commands::Intent::Unreport", "Remove a report recorded by mistake: its rows, its outcome line and its file, which --to-tmp moves to resources/tmp/"],
        "intent approve" => ["Commands::Intent::Approve", "Write the owner's go-ahead for an intent; no node of it is claimed without it"],
        "intent judge" => ["Commands::Intent::Judge", "Print the steps that start the judge of an intent"],
        "intent verdict" => ["Commands::Intent::Verdict", "Record the verdict of the next review round of an intent"],
        "intent grant" => ["Commands::Intent::Grant", "Grant one extra review round, on the owner's word, to an intent whose rounds are used"],
        "intent handover" => ["Commands::Intent::Handover", "Hand the last gap of an intent whose rounds are used to a follow-up intent, on the owner's word, so the intent can end"],
        "intent spec" => ["Commands::Intent::Spec", "Write spec.md from a file with --from, then print the grilling method, how done criteria are written, and the open decisions of spec.md"],
        "intent discover" => ["Commands::Intent::Discover", "Record deterministic retrieval candidates for an intent"],
        "intent context" => ["Commands::Intent::Context", "Read or submit selected retrieval context for an intent"],
        "intent show" => ["Commands::Intent::Show", "Print one intent's status, criteria, decisions, rulings and nodes"],
        "intent brief" => ["Commands::Intent::Brief", "Print an intent's goal, criteria, rulings, ready nodes and command usage"],
        "intent link" => ["Commands::Intent::Link", "Write a typed link from an intent to a ref"],
        "intent unlink" => ["Commands::Intent::Unlink", "Remove a link"],
        "intent archive" => ["Commands::Intent::Archive", "Archive an intent directory"],
        "intent repair" => ["Commands::Intent::Repair", "Apply the folder layout to one intent folder, or to every one with --all"],
        "intent unarchive" => ["Commands::Intent::Unarchive", "Restore an archived intent's directory exactly as it was archived"]
      },
      "project" => {
        "project list" => ["Commands::Project::List", "List the registered projects with their paths"],
        "project load" => ["Commands::Project::Load", "Print a short digest of each named project to warm the context before the next ask"],
        "project new" => ["Commands::Project::New", "Register a project and leave its store ready for intent new"],
        "project links" => ["Commands::Project::Links", "List the links that name an intent or a ruling this store lacks"]
      },
      "session" => {
        "session note" => ["Commands::Session::Note", "Write the one prose line of this session"]
      },
      "config" => {
        "config" => ["Commands::Config", "Pick which on/off settings are on, on the choice screen"],
        "config list" => ["Commands::Config::List", "List every setting with its value, globally or for one harness"],
        "config get" => ["Commands::Config::Get", "Print the value of one setting"],
        "config set" => ["Commands::Config::Set", "Write one setting to the settings rows, globally or for one harness"]
      },
      "store" => {
        "store backup" => ["Commands::Store::Backup", "Copy one store's databases into a new backup folder"],
        "store backup list" => ["Commands::Store::Backup::List", "List one store's backups with status and goal, flagging a missing or changed file"],
        "store backup purge" => ["Commands::Store::Backup::Purge", "Delete one store's backups; give one of --all, --failed, --interrupted or --older-than"],
        "store backup restore" => ["Commands::Store::Backup::Restore", "Replace one store's databases with those of a done backup"],
        "store migration list" => ["Commands::Store::Migration::List", "Print the ledger rows of one store and what a down would undo now"],
        "store migration down" => ["Commands::Store::Migration::Down", "Put back the rows the newest migration of one store kept in legacy.db and remove its version, after a backup"],
        "store migration purge" => ["Commands::Store::Migration::Purge", "Remove the rows one migration of a store kept in legacy.db, so a down can no longer undo it"],
        "store sync up" => ["Commands::Store::Sync::Up", "Read the files changed by hand into rows"],
        "store sync down" => ["Commands::Store::Sync::Down", "Write the rows that changed into files"]
      },
      "document" => {
        "document get" => ["Commands::Document::Get", "Fetch the current text of one document; an older pinned reference is named as changed"],
        "document batch" => ["Commands::Document::Batch", "Fetch qualified documents in request order"]
      },
      "architecture" => {
        "architecture status" => ["Commands::Architecture::Status", "Tell the agent to check the architecture map with its own tool"],
        "architecture refresh" => ["Commands::Architecture::Refresh", "Tell the agent to regenerate the architecture map with its own tool"]
      },
      **WORK_FAMILIES
    }.each_value(&:freeze).freeze

    # Every command in one hash, the families in order.
    TABLE = FAMILIES.values.reduce({}, :merge).freeze
  end
end
