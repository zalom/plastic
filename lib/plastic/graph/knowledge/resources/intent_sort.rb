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
        # neither recorded nor mandatory moves to resources/tmp/; with none, the reports folder is left as it is. A recorded or
        # mandatory report is never rewritten, and every file of the intent folder that it links to stays where it is.
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

          def destinations = (@destinations ||= files.to_h { |rel| [rel, destination(rel)] }.compact)

          def destination(rel) = (Classification.destination(rel) || unasked_destination(rel) unless linked_from_listed.include?(rel))

          def unasked_destination(rel)
            return unless @reports && Knowledge::Reports.report?(rel) && !Classification.machine?(rel) && !listed?(rel)

            "resources/tmp/#{rel.delete_prefix(Knowledge::Reports::FOLDER)}"
          end

          def intent_id = SyncSelection.intent_of(@dir)

          def listed?(rel) = !@reports.nil? && Knowledge::Reports.report?(rel) && @reports.listed?(intent_id, rel)

          # The paths inside the intent folder that a recorded or mandatory report links to.
          def linked_from_listed
            @linked_from_listed ||= files.select { |rel| IntentSort.linked?(rel) && listed?(rel) }
              .flat_map { |rel| LinkRewrite.targets("#{@dir}/#{rel}", text(rel)) }
              .filter_map { |path| path.delete_prefix("#{@dir}/") if path.start_with?("#{@dir}/") }.to_set
          end

          def text(rel) = @folder.read("#{@dir}/#{rel}").force_encoding(Encoding::UTF_8)

          def rewriter = (@rewriter ||= LinkRewrite.new(@moved.call, KnownFiles.new(@folder)))

          # A listed report keeps its bytes: its links are read against no move.
          def rewriter_of(rel) = listed?(rel) ? LinkRewrite.new({}, KnownFiles.new(@folder)) : rewriter

          def results
            @results ||= files.select { |rel| IntentSort.linked?(rel) }.map do |rel|
              was = text(rel)
              Linked.new(rel, was, rewriter_of(rel).call("#{@dir}/#{rel}", was))
            end
          end
        end
      end
    end
  end
end
