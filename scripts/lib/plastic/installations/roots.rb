# frozen_string_literal: true

require "pathname"

module Plastic
  module Installations
    # The folders of one harness that an install may write into and a removal
    # may delete from.
    Roots = Data.define(:paths) do
      def inside?(path) = paths.any? { |root| File.expand_path(path).start_with?("#{root}/") }

      def plastic_folders(files) = files.flat_map { |file| folders_of(file) }.uniq

      private

      def folders_of(file) = Pathname(file).dirname.ascend.map(&:to_s).select { |folder| plastic?(folder) }

      def plastic?(folder) = inside?(folder) && File.basename(folder).start_with?("plastic")
    end
  end
end
