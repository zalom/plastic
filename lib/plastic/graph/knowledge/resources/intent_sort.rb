# frozen_string_literal: true

require_relative "classification"
require_relative "link_rewrite"
require_relative "move"
require_relative "../legacy_path"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # The sort of one intent folder: the files that move, and the text of the files whose links change.
        # Paths are relative to the store folder.
        class IntentSort
          Rewrite = Data.define(:path, :text, :was)
          Linked = Data.define(:rel, :was, :found) do
            def rewrite(dir, destinations) = Rewrite.new("#{dir}/#{destinations.fetch(rel, rel)}", found.text, was)

            def changed? = found.text != was

            def unresolved_in(dir) = found.unresolved.map { |link| "#{dir}/#{rel}: #{link}" }
          end

          def self.linked?(rel) = %w[md html].include?(File.extname(rel).delete_prefix(".").downcase) && !LegacyPath.legacy?(rel)

          def initialize(folder, dir)
            @folder = folder
            @dir = dir
          end

          def moves = destinations.map { |from, to| Move.new("#{@dir}/#{from}", "#{@dir}/#{to}") }

          def rewrites = results.select(&:changed?).map { |linked| linked.rewrite(@dir, destinations) }

          def unresolved = results.flat_map { |linked| linked.unresolved_in(@dir) }

          private

          def files = (@files ||= Dir.glob("**/*", File::FNM_DOTMATCH, base: @folder.path(@dir)).select { |rel| @folder.exist?("#{@dir}/#{rel}") }.sort)

          def destinations = (@destinations ||= files.to_h { |rel| [rel, Classification.destination(rel)] }.compact)

          def results
            @results ||= files.select { |rel| IntentSort.linked?(rel) }.map do |rel|
              was = @folder.read("#{@dir}/#{rel}").force_encoding(Encoding::UTF_8)
              Linked.new(rel, was, LinkRewrite.new(destinations, files).call(rel, was))
            end
          end
        end
      end
    end
  end
end
