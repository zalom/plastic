# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # A Markdown file of an intent's folder, such as spec.md or
    # actions/ACTION_1.md. `path` is relative to the folder; the body is the
    # file, byte for byte.
    Document = Data.define(:intent_id, :path, :body, :updated_at, :origin_id) do
      include Record
    end
  end
end
