# frozen_string_literal: true

require_relative "../../layout"

module Plastic
  module Graph
    module Work
      # The schemas of one intent's nodes: the file resources/tmp/schemas/NODE.json of the intent folder, found by the
      # node's id. Plastic names the file and finds a stray one; the worker's harness checks the output against it.
      class Schemas
        FOLDER = "#{Layout.resource(:tmp)}schemas"

        # `folder` is the store folder and `dir` the intent folder in it.
        def initialize(folder, dir)
          @folder = folder
          @dir = dir
        end

        # The full path of the schema of the node, or nil when the node has no schema file.
        def path(node_id) = (@folder.path(file(node_id)) if @folder.exist?(file(node_id)))

        # The ids the schema files name, in order.
        def ids = Dir.glob("*.json", base: @folder.path("#{@dir}/#{FOLDER}")).map { |name| File.basename(name, ".json") }.sort

        # The path of the schema of the node inside the intent folder.
        def relative(node_id) = "#{FOLDER}/#{node_id}.json"

        private

        def file(node_id) = "#{@dir}/#{relative(node_id)}"
      end
    end
  end
end
