# frozen_string_literal: true

require_relative "../workflow"

module Plastic
  class CodeWorkflow < Workflow
    # A step that reads, sets facts or prints, and changes nothing on disk.
    # It runs on every call and never ends one.
    Read = Data.define(:name, :body) do
      def run(ctx, _workflow)
        body.call(ctx)
        nil
      end
    end
  end
end
