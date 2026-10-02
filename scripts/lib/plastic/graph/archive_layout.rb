# frozen_string_literal: true

require_relative "archive_tree"

module Plastic
  module Graph
    # Checks the complete layout before restoration writes any entry.
    module ArchiveLayout
      KINDS = %w[directory file link].freeze

      def self.validate(rows)
        by_path = rows.to_h { |row| [row[:path], row] }
        raise ArchiveTree::Error, "archive snapshot has no directory root" unless by_path.dig("", :kind) == "directory"

        rows.each { |row| validate_entry(row, by_path) }
        rows
      end

      def self.validate_entry(row, by_path)
        validate_path(row[:path])
        raise ArchiveTree::Error, "invalid archive entry kind #{row[:kind]}" unless KINDS.include?(row[:kind])

        segments = row[:path].split("/")
        parents = (1...segments.size).map { |size| segments.take(size).join("/") }
        parents.each do |parent|
          raise ArchiveTree::Error, "archive parent #{parent} is not a directory" unless by_path.dig(parent, :kind) == "directory"
        end
      end

      def self.validate_path(relative)
        invalid = !relative.empty? && relative.split("/", -1).any? { |part| ["", ".", ".."].include?(part) }
        raise ArchiveTree::Error, "invalid archive path #{relative}" if invalid || relative.include?("\0")
      end
    end
  end
end
