# frozen_string_literal: true

require_relative "classification"
require_relative "known_files"
require_relative "link_rewrite"
require_relative "move"
require_relative "../legacy_path"
require_relative "../reports"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # The sort of one intent folder: the files that move, and the text of the files whose links change.
        # Paths are relative to the store folder. Given the store's `reports`, a file of resources/output/reports/ that is
        # neither recorded nor mandatory moves to resources/tmp/; with none, the reports folder is left as it is.
        class IntentSort
          Rewrite = Data.define(:path, :text, :was) do
            def undo(folder) = (folder.write(path, was) if folder.exist?(path))
          end
          Linked = Data.define(:rel, :was, :found) do
            def rewrite(dir, moved) = Rewrite.new(moved.fetch("#{dir}/#{rel}", "#{dir}/#{rel}"), found.text, was)

            def changed? = found.text != was

            def unresolved_in(dir) = found.unresolved.map { |link| "#{dir}/#{rel}: #{link}" }

            def changed_in(dir) = found.changed.map { |link| "#{dir}/#{rel}: #{link}" }
          end

          def self.linked?(rel) = %w[md html].include?(File.extname(rel).delete_prefix(".").downcase) && !LegacyPath.legacy?(rel)

          def initialize(folder, dir, moved, reports = nil)
            @folder = folder
            @dir = dir
            @moved = moved
            @reports = reports
          end

          def moves = destinations.map { |from, to| Move.new("#{@dir}/#{from}", "#{@dir}/#{to}") }

          # The moves of the reports that are neither recorded nor mandatory.
          def unasked = moves.select { |move| Knowledge::Reports.report?(move.inside_from) }

          def rewrites = results.select(&:changed?).map { |linked| linked.rewrite(@dir, @moved.call) }

          def unresolved = results.flat_map { |linked| linked.unresolved_in(@dir) }

          def changed = results.flat_map { |linked| linked.changed_in(@dir) }

          private

          def files = (@files ||= Dir.glob("**/*", File::FNM_DOTMATCH, base: @folder.path(@dir)).select { |rel| @folder.exist?("#{@dir}/#{rel}") }.sort)

          def destinations = (@destinations ||= files.to_h { |rel| [rel, Classification.destination(rel) || unasked_destination(rel)] }.compact)

          def unasked_destination(rel)
            return unless @reports && Knowledge::Reports.report?(rel) && !@reports.listed?(intent_id, rel)

            "resources/tmp/#{rel.delete_prefix(Knowledge::Reports::FOLDER)}"
          end

          def intent_id = SyncSelection.intent_of(@dir)

          def rewriter = (@rewriter ||= LinkRewrite.new(@moved.call, KnownFiles.new(@folder)))

          def results
            @results ||= files.select { |rel| IntentSort.linked?(rel) }.map do |rel|
              was = @folder.read("#{@dir}/#{rel}").force_encoding(Encoding::UTF_8)
              Linked.new(rel, was, rewriter.call("#{@dir}/#{rel}", was))
            end
          end
        end
      end
    end
  end
end
