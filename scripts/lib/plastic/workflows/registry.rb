# frozen_string_literal: true

module Plastic
  module Workflows
    # Every workflow key, listed by hand. A key is the lane, then the class
    # name in snake case: :code_close_intent is Workflows::CloseIntent in
    # workflows/close_intent.rb, a CodeWorkflow. Workflow.fetch loads a file
    # only when a routine asks for its key, and a key missing here fails
    # `verify` before any step runs. Each family owns its own section.
    REGISTRY = [
      # Storage: intents and the sync of a store folder with its rows.
      :code_write_intent, :code_sync_up, :code_sync_down, :code_add_ruling, :code_revise_intent, :code_note_intent, :code_show_spec, :code_approve_intent, :code_prepare_judge, :code_prepare_verdict, :agent_judge_intent, :code_record_verdict, :code_start_auto, :code_pick_delivery,
      :code_show_lock,
      :code_preview_sync, :code_preview_sync_down,
      :code_check_graph, :code_ready_graph, :code_show_graph, :code_show_intent, :code_show_brief, :code_pick_next,
      # Knowledge graph: typed links between intents and rulings.
      :code_add_link, :code_remove_link,
      # Roadmaps: batches and items held as rows, with a derived state per item.
      :code_create_roadmap, :code_write_roadmap_batch, :code_add_roadmap_item, :code_show_roadmap, :code_next_roadmap,
      :code_drop_roadmap_item, :code_start_roadmap_item, :code_check_roadmap, :code_log_roadmap,
      :code_remove_roadmap_edge,

      :code_delivery_next, :agent_advance_delivery, :code_prepare_ending, :agent_finish_intent, :code_close_intent, :agent_wind_down_intent,
      :code_discover_retrieval, :agent_external_agent_workflow,
      # Retrieval reads: search, qualified documents and the saved context of an intent.
      :code_search, :code_get_document, :code_batch_documents, :code_check_context_owner, :code_read_context,
      :code_submit_context,
      # Architecture: prompts only; the agent maps the code with the tool it chose.
      :agent_check_architecture, :agent_check_merge, :code_prepare_abandon, :agent_revert_intent, :code_abandon_intent, :agent_refresh_architecture,
      # Sessions: the one prose line a session writes about itself.
      :code_write_note,
      # Archive: taking an intent off the checkout and printing it back.
      :code_archive_intent, :code_restore_intent,
      # Backups: one folder per backup of one store, with purge and restore.
      :code_preview_backup, :code_backup, :code_backup_list,
      :code_preview_backup_purge, :code_backup_purge, :code_preview_backup_restore, :code_backup_restore,
      # Distribution: the installer commands over the running package and the home.
      :code_show_version, :code_check_health, :code_preview_install, :code_install_plastic, :agent_offer_enola,
      :code_preview_update, :code_update_plastic,
      :code_preview_rollback, :code_rollback_release, :code_preview_uninstall, :code_uninstall_plastic,
      # Work graph: building and moving the nodes and edges of one intent.
      :code_add_node, :code_remove_node, :code_add_edge, :code_remove_edge,
      :code_claim_node, :code_release_node, :code_done_node, :code_fail_node, :code_ask_node, :code_impede_node, :code_resolve_node
    ].freeze
  end
end
