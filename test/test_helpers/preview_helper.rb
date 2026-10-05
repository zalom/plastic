# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Plastic
  class TestCase
    # Committed homes of their own, for the tests of a preview. The test's
    # own home sits inside a transaction, which a copy of its databases
    # cannot see; these homes are plain files on disk.
    module PreviewHelper
      CLOSING = "preview complete; the original store was not changed"

      # One call run twice: a preview on the first home and the apply on an
      # identical second home, with the first home's files before and after.
      Twins = Data.define(:previewed, :applied, :before, :after, :first, :second) do
        def changed_paths = (before.keys | after.keys).reject { |path| before[path] == after[path] }

        def previewed_lines
          lines(previewed.out).filter_map { |line| line.delete_prefix("preview: ").sub("would write:", "wrote:") unless dropped?(line) }
        end

        def applied_lines = lines(applied.out)

        def preview_paths = previewed.out.lines(chomp: true).filter_map { |line| line.delete_prefix("preview: would ") if line.start_with?("preview: would ") }

        private

        def dropped?(line) = line == CLOSING || line.start_with?("preview: would add", "preview: would change", "preview: would remove")

        def lines(text)
          text.lines(chomp: true).reject { |line| line.empty? || line.start_with?("next:", "because:") }
            .map { |line| line.gsub(first, "HOME").gsub(second, "HOME").squeeze(" ") }
        end
      end

      def call_in(home, *argv) = plastic(*argv, env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE)

      def with_home
        Dir.mktmpdir("plastic-preview-home") do |root|
          yield File.join(root, ".plastic")
        ensure
          Plastic::Graph::Database::ConnectionPool.release(root)
        end
      end

      def home_graphs(home) = Plastic::Graph.open(home:, store: "global")

      def twin_run(*argv)
        Dir.mktmpdir("plastic-twins") do |root|
          first = File.join(root, "first", ".plastic")
          second = File.join(root, "second", ".plastic")
          yield first
          FileUtils.mkdir_p(File.dirname(second))
          FileUtils.cp_r(first, File.dirname(second))
          before = snapshot(first)
          previewed = call_in(first, *argv, "--dry-run")
          after = snapshot(first)
          Twins.new(previewed:, applied: call_in(second, *argv), before:, after:, first:, second:)
        ensure
          Plastic::Graph::Database::ConnectionPool.release(root)
        end
      end

      def assert_preview_matches_apply(twin)
        assert_equal [], twin.changed_paths
        assert_equal twin.applied.code, twin.previewed.code, [twin.previewed.out, twin.previewed.err].inspect
        assert_equal twin.applied_lines, twin.previewed_lines
        assert_equal twin.applied.err, twin.previewed.err
        assert_includes twin.previewed.out, "#{CLOSING}\n"
      end

      def seed_intents(home, *titles) = titles.each { |title| call_in(home, "intent", "new", title) }

      def seed_nodes(home, *titles) = titles.each { |title| call_in(home, "node", "add", "1", title, "--criterion", "done") }

      def mark_done_in(home, intent_id)
        home_graphs(home).databases.fetch(:work).transaction do |batch|
          batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :id", id: intent_id)
        end
      end

      def seed_roadmap(home, *items)
        call_in(home, "roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d")
        items.each { |item| call_in(home, "roadmap", "add", "r1", "1", item, "--title", item.upcase) }
      end
    end
  end
end
