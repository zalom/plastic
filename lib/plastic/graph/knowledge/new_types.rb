# frozen_string_literal: true

require_relative "../../layout"

module Plastic
  module Graph
    module Knowledge
      class NewTypes
        OUTPUT = "#{Layout.output_root}**/*"

        def initialize(folder)
          @folder = folder
        end

        def call = @folder.sync.selection.new_types(output_files)

        private

        def output_files = @folder.intent_dirs.flat_map { |dir| files_in(dir) }

        def files_in(dir) = Dir.glob(OUTPUT, base: @folder.path(dir)).select { |rel| @folder.exist?("#{dir}/#{rel}") }
      end
    end
  end
end
