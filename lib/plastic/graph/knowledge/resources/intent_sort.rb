# frozen_string_literal: true

require_relative "classification"
require_relative "link_rewrite"
require_relative "../legacy_path"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # The sort of one intent folder: the files that move, and the text of the files whose links change.
        # Paths are relative to the store folder.
        class IntentSort
          Move = Data.define(:from, :to)
          Rewrite = Data.define(:path, :text, :was)
          LINKED = %w[md html].freeze

          def initialize(folder, dir)
            @folder = folder
            @dir = dir
          end

          def moves = destinations.map { |from, to| Move.new("#{@dir}/#{from}", "#{@dir}/#{to}") }

          def rewrites = results.filter_map { |rel, was, found| Rewrite.new("#{@dir}/#{destinations.fetch(rel, rel)}", found.text, was) if found.text != was }

          def unresolved = results.flat_map { |rel, _was, found| found.unresolved.map { |link| "#{@dir}/#{rel}: #{link}" } }

          private

          def files = (@files ||= Dir.glob("**/*", File::FNM_DOTMATCH, base: @folder.path(@dir)).select { |rel| @folder.exist?("#{@dir}/#{rel}") }.sort)

          def destinations = (@destinations ||= files.to_h { |rel| [rel, Classification.destination(rel)] }.compact)

          def results
            @results ||= files.select { |rel| linked?(rel) }.map do |rel|
              was = @folder.read("#{@dir}/#{rel}").force_encoding(Encoding::UTF_8)
              [rel, was, LinkRewrite.new(destinations, files).call(rel, was)]
            end
          end

          def linked?(rel) = LINKED.include?(File.extname(rel).delete_prefix(".").downcase) && !LegacyPath.legacy?(rel)
        end
      end
    end
  end
end
