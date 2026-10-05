# frozen_string_literal: true

require "fileutils"
require_relative "../backup"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # One private archive waiting for publication with its metadata row.
        class Staged
          attr_reader :row, :path

          def initialize(row:, path:)
            @row = row
            @path = path
            @published = false
          end

          def publish_to(directory)
            File.link(path, destination(directory))
            @published = true
            FileUtils.rm_f(path)
            row
          end

          def discard_from(directory)
            FileUtils.rm_f(path)
            FileUtils.rm_f(destination(directory)) if @published
          end

          private

          def destination(directory) = File.join(directory, row.fetch(:name))
        end
      end
    end
  end
end
