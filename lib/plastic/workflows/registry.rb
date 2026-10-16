# frozen_string_literal: true

module Plastic
  module Workflows
    # Every workflow key, listed by hand, with the class path under Workflows
    # that runs it. A key is the lane, then the words of its job and never
    # changes, because an open routine run stores it; the class path follows
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
      code_show_spec: "Code::Intent::Spec",
      code_approve_intent: "Code::Intent::Approve",
      code_prepare_judge: "Code::Intent::Judge",
      code_prepare_verdict: "Code::Intent::Verdict::Prepare",
      agent_judge_intent: "Agent::Intent::Judge",
      code_record_verdict: "Code::Intent::Verdict",
      code_start_auto: "Code::Auto",
      code_pick_delivery: "Code::Auto::Pick",
      code_show_lock: "Code::Intent::Lock::Status",
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
      # Roadmaps: batches and items held as rows, with a derived state per item.
      code_create_roadmap: "Code::Roadmap::New",
      code_write_roadmap_batch: "Code::Roadmap::Batch",
      code_add_roadmap_item: "Code::Roadmap::Add",
      code_show_roadmap: "Code::Roadmap::Show",
      code_next_roadmap: "Code::Roadmap::Next",
      code_drop_roadmap_item: "Code::Roadmap::Drop",
      code_open_roadmap_item: "Code::Roadmap::Open",
      code_check_roadmap: "Code::Roadmap::Check",
      code_log_roadmap: "Code::Roadmap::Log",
      code_remove_roadmap_edge: "Code::Roadmap::Edge::Remove",

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
      agent_check_merge: "Agent::Intent::End::CheckMerge",
      code_prepare_abandon: "Code::Intent::Abandon::Prepare",
      agent_revert_intent: "Agent::Intent::Abandon",
      code_abandon_intent: "Code::Intent::Abandon",
      agent_refresh_architecture: "Agent::Architecture::Refresh",
      # Sessions: the one prose line a session writes about itself.
      code_write_note: "Code::Session::Note",
      # Archive: taking an intent off the checkout and printing it back.
      code_archive_intent: "Code::Intent::Archive",
      code_unarchive_intent: "Code::Intent::Unarchive",
      # Backups: one folder per backup of one store, with purge and restore.
      code_preview_backup: "Code::Backup::Preview",
      code_backup: "Code::Backup",
      code_backup_list: "Code::Backup::List",
      code_preview_backup_purge: "Code::Backup::Purge::Preview",
      code_backup_purge: "Code::Backup::Purge",
      code_preview_backup_restore: "Code::Backup::Restore::Preview",
      code_backup_restore: "Code::Backup::Restore",
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
      code_release_node: "Code::Node::Release",
      code_done_node: "Code::Node::Done",
      code_fail_node: "Code::Node::Fail",
      code_ask_node: "Code::Node::Ask",
      code_impede_node: "Code::Node::Impede",
      code_resolve_node: "Code::Node::Resolve"
    }.freeze
  end
end
