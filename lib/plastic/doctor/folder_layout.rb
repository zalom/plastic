# frozen_string_literal: true

require_relative "check"
require_relative "../errors"
require_relative "../scope"
require_relative "../graph"
require_relative "../graph/knowledge/store_folder"
require_relative "../graph/knowledge/reports"
require_relative "../graph/knowledge/repair/plan"
require_relative "../graph/knowledge/repair/store_leftovers"
require_relative "folder_layout/broken_folder"
require_relative "folder_layout/root_entries"

module Plastic
  module Doctor
    # Whether the folders of one store follow the layout: one finding for each intent folder that breaks it, saying
    # what is wrong there, one for the retired entries of the store folder, and one for each entry that holds data the
    # layout does not allow or that the layout does not name at the store root, which is left to a person. A done or
    # abandoned intent that lacks a file its state requires gets a row with no repair, since its work is not written
    # again. Given the reports of the settings, it reads the `reported` lines of the store, when its database exists,
    # and judges the reports folder as the repair does. It writes no file.
    class FolderLayout
      Knowledge = Graph::Knowledge
      COMMAND = "plastic intent repair"
      OPEN = ->(home, slug) { Graph.open(home:, store: slug).databases.fetch(:store) }
      INTENTS = "SELECT intent_id, status FROM intents"

      def self.checks(scope, reports: nil)
        slugs = [Scope::GLOBAL, *scope.projects.keys].uniq
        slugs.flat_map { |slug| new(scope.plastic_home, slug, reports).checks }
      end

      def initialize(home, slug, reports)
        @home = home
        @slug = slug
        @folder = Knowledge::StoreFolder.new(File.join(home, "stores", slug))
        @reports = reports
      end

      def checks
        return [] unless File.directory?(@folder.root)

        found = [*folder_checks, *leftover_checks, *root_checks]
        [*(found.empty? ? [Check.ok(label, "every intent folder follows the layout")] : found), *missing_checks]
      rescue Refused => error
        [finding(label, error.message)]
      end

      attr_reader :slug

      # A finding of this store whose repair is the repair command.
      def finding(label, text) = Check.finding(label, text, "#{COMMAND} --all --project #{@slug}")

      private

      def plan = (@plan ||= Knowledge::Repair::Plan.new(@folder, reports: store_reports, states: closed_states))

      def missing_checks = plan.missing.to_a.map { |missing| Check.new("layout #{@slug} #{File.basename(missing.dir)}:", missing.text, nil) }

      def folder_checks = BrokenFolders.new(plan, @folder).to_a.flat_map { |broken| broken.checks(self) }

      def leftover_checks
        leftovers = Knowledge::Repair::StoreLeftovers.new(@folder)
        [retired_check(leftovers.removals), *leftovers.kept.map { |rel, why| kept_check(rel, why) }].compact
      end

      def retired_check(removals) = (finding("layout #{@slug} store/:", "retired: #{removals.join(", ")}") unless removals.empty?)

      def kept_check(rel, why) = Check.finding("layout #{@slug} #{rel}:", why, "move #{rel} out of the store folder by hand, then run plastic doctor again")

      # One finding for each entry at the store root that the layout does not name, which is left to a person.
      def root_checks = RootEntries.new(@folder.root).to_a.map { |rel| unnamed_check(rel) }

      def unnamed_check(rel)
        Check.finding("layout #{@slug} #{rel}:", Knowledge::Repair::StoreLeftovers::UNNAMED, "move #{rel} out of the store by hand, then run plastic doctor again")
      end

      def label = "layout #{@slug}:"

      # The reports of the settings with the recorded ones of the store; nil leaves the reports folder unjudged.
      def store_reports
        pairs = @reports && store_rows(Knowledge::Reports::RECORDED)&.map { |row| row.values_at("intent_id", "path") }
        pairs && Knowledge::Reports.new(mandatory: @reports.mandatory, recorded: -> { pairs })
      end

      # The status of each done or abandoned intent of the store by its id, none when its database cannot be read.
      def closed_states = Knowledge::Repair::MissingFiles.closed((store_rows(INTENTS) || []).map { |row| row.values_at("intent_id", "status") })

      # The rows of a query of the store database, none when it has no database yet; nil when the database cannot be read,
      # which the check of the store names.
      def store_rows(sql)
        return [] unless File.file?(@folder.path(Graph::Schema.file(:knowledge)))

        OPEN.call(@home, @slug).rows(sql)
      rescue Graph::Database::Error
        nil
      end
    end
  end
end
