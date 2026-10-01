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
      :code_write_intent, :code_sync_up, :code_sync_down
    ].freeze
  end
end
