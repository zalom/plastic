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
      :code_write_intent, :code_sync_up, :code_sync_down, :code_add_ruling, :code_show_spec, :code_start_auto,
      :code_preview_sync,
      :code_check_graph, :code_ready_graph, :code_show_graph, :code_show_intent, :code_show_brief, :code_pick_next,
      # Knowledge graph: typed links between intents and rulings.
      :code_add_link, :code_remove_link,
      # Roadmaps: batches and items held as rows, with a derived state per item.
      :code_write_roadmap_batch, :code_add_roadmap_item, :code_show_roadmap, :code_next_roadmap,
      :code_drop_roadmap_item, :code_start_roadmap_item, :code_check_roadmap, :code_log_roadmap,
      :code_remove_roadmap_edge,

      :code_delivery_next, :agent_advance_delivery, :code_prepare_ending, :agent_finish_intent, :code_close_intent,
      # Sessions: the one prose line a session writes about itself.
      :code_write_note,
      # Archive: taking an intent off the checkout and printing it back.
      :code_choose_archive, :code_archive_intent, :code_restore_intent,
      # Backups: one gzipped tar of every database on the machine.
      :code_backup, :code_backup_list,
      # Work graph: building and moving the nodes and edges of one intent.
      :code_add_node, :code_remove_node, :code_add_edge, :code_remove_edge,
      :code_claim_node, :code_release_node, :code_done_node, :code_fail_node, :code_park_node, :code_answer_node
    ].freeze
  end
end
