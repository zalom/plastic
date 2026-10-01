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
      :code_write_intent, :code_sync_up, :code_sync_down,
      # Sessions: the one prose line a session writes about itself.
      :code_write_note,
      # Work graph: building and moving the nodes and edges of one intent.
      :code_add_node, :code_remove_node, :code_add_edge, :code_remove_edge,
      :code_claim_node, :code_release_node, :code_done_node, :code_fail_node, :code_park_node, :code_answer_node
    ].freeze
  end
end
