# frozen_string_literal: true

module Plastic
  module Workflows
    # Every workflow key, listed by hand, with the class path under Workflows
    # that runs it. A key is the lane, then the words of its job and never
    # changes, because an open command run stores it; the class path follows
    # the command the workflow belongs to: :code_close_intent is
    # Workflows::Code::Intent::End in workflows/code/intent/end.rb, a
    # CodeWorkflow. Workflow.fetch loads a file only when a routine asks for
    # its key, and a key missing here fails `verify` before any step runs.
    # Each family owns its own section.
    REGISTRY = {
      # Storage: intents and the sync of a store folder with its rows.
      code_write_intent: "Code::Intent::New",
      code_sync_up: "Code::Sync::Up",
      code_sync_down: "Code::Sync::Down",
      code_add_ruling: "Code::Intent::Rule",
      code_revise_intent: "Code::Intent::Revise",
      code_note_intent: "Code::Intent::Note",
      code_report_intent: "Code::Intent::Report",
      code_unreport_intent: "Code::Intent::Unreport",
      code_show_spec: "Code::Intent::Spec",
      code_write_spec: "Code::Intent::Spec::Write",
      code_write_outcome: "Code::Intent::Outcome",
      code_approve_intent: "Code::Intent::Approve",
      code_prepare_judge: "Code::Intent::Judge",
      code_prepare_verdict: "Code::Intent::Verdict::Prepare",
      agent_judge_intent: "Agent::Intent::Judge",
      code_record_verdict: "Code::Intent::Verdict",
      code_start_intent: "Code::Intent::Start",
      code_preview_sync: "Code::Sync::Up::Preview",
      code_preview_sync_down: "Code::Sync::Down::Preview",
      code_check_graph: "Code::Graph::Check",
      code_ready_graph: "Code::Graph::Ready",
      code_show_graph: "Code::Graph::Show",
      code_show_intent: "Code::Intent::Show",
      code_show_brief: "Code::Intent::Brief",
      code_pick_next: "Code::Next",
      # Knowledge graph: typed links between intents and rulings.
      code_add_link: "Code::Intent::Link",
      code_remove_link: "Code::Intent::Unlink",

      code_delivery_next: "Code::Intent::Brief::Next",
      agent_advance_delivery: "Agent::Shared::AdvanceDelivery",
      code_prepare_ending: "Code::Intent::End::Prepare",
      agent_finish_intent: "Agent::Intent::End",
      code_close_intent: "Code::Intent::End",
      agent_wind_down_intent: "Agent::Shared::WindDownIntent",
      code_discover_retrieval: "Code::Intent::Discover",
      agent_external_agent_workflow: "Agent::Intent::Discover",
      # Retrieval reads: search, qualified documents and the saved context of an intent.
      code_search: "Code::Search",
      code_get_document: "Code::Document::Get",
      code_batch_documents: "Code::Document::Batch",
      code_check_context_owner: "Code::Intent::Context::CheckOwner",
      code_read_context: "Code::Intent::Context::Read",
      code_submit_context: "Code::Intent::Context",
      # Architecture: prompts only; the agent maps the code with the tool it chose.
      agent_check_architecture: "Agent::Architecture::Status",
      agent_check_delivery: "Agent::Intent::End::CheckDelivery",
      code_prepare_abandon: "Code::Intent::Abandon::Prepare",
      agent_revert_intent: "Agent::Intent::Abandon",
      code_abandon_intent: "Code::Intent::Abandon",
      agent_refresh_architecture: "Agent::Architecture::Refresh",
      # Sessions: the one prose line a session writes about itself.
      code_write_note: "Code::Session::Note",
      # Archive: taking an intent off the checkout and printing it back.
      code_archive_intent: "Code::Intent::Archive",
      code_unarchive_intent: "Code::Intent::Unarchive",
      # Repair: the folder layout applied to old intent folders.
      code_preview_repair_intent: "Code::Intent::Repair::Preview",
      code_repair_intent: "Code::Intent::Repair",
      # Backups: one folder per backup of one store, with purge and restore.
      code_preview_backup: "Code::Backup::Preview",
      code_backup: "Code::Backup",
      code_backup_list: "Code::Backup::List",
      code_preview_backup_purge: "Code::Backup::Purge::Preview",
      code_backup_purge: "Code::Backup::Purge",
      code_preview_backup_restore: "Code::Backup::Restore::Preview",
      code_backup_restore: "Code::Backup::Restore",
      # Migrations: the ledger of one store, and the down and purge of its legacy rows.
      code_migration_down: "Code::Migration::Down",
      code_migration_purge: "Code::Migration::Purge",
      code_migration_list: "Code::Migration::List",
      # Projects: the list of registered projects.
      code_resume_graph: "Code::Graph::Resume",
      code_lapsed_graph: "Code::Graph::Lapsed",
      code_load_projects: "Code::Project::Load",
      code_list_projects: "Code::Project::List",
      code_list_chat: "Code::Chat::List",
      # Settings: the config file read and written one key at a time.
      code_list_config: "Code::Config::List",
      code_get_config: "Code::Config::Get",
      code_set_config: "Code::Config::Set",
      # Distribution: the installer commands over the running package and the home.
      code_show_version: "Code::Version",
      code_check_health: "Code::Doctor",
      code_preview_install: "Code::Install::Preview",
      code_install_plastic: "Code::Install",
      agent_offer_enola: "Agent::Install",
      code_choose_harnesses: "Code::Init::Choose",
      code_install_harnesses: "Code::Init",
      code_choose_installations: "Code::Uninstall::Choose",
      code_preview_update: "Code::Update::Preview",
      code_update_plastic: "Code::Update",
      code_preview_rollback: "Code::Rollback::Preview",
      code_rollback_release: "Code::Rollback",
      code_preview_uninstall: "Code::Uninstall::Preview",
      code_uninstall_plastic: "Code::Uninstall",
      # Work graph: building and moving the nodes and edges of one intent.
      code_add_node: "Code::Node::Add",
      code_remove_node: "Code::Node::Remove",
      code_add_edge: "Code::Edge::Add",
      code_remove_edge: "Code::Edge::Remove",
      code_claim_node: "Code::Node::Claim",
      code_renew_node: "Code::Node::Renew",
      code_release_node: "Code::Node::Release",
      code_done_node: "Code::Node::Done",
      code_fail_node: "Code::Node::Fail",
      code_ask_node: "Code::Node::Ask",
      code_impede_node: "Code::Node::Impede",
      code_resolve_node: "Code::Node::Resolve",

      # Statuses: parking started work with its reason.
      code_park_intent: "Code::Intent::Park",

      # Review rounds: the owner grants one extra round.
      code_grant_round: "Code::Intent::Grant"
    }.freeze
  end
end
