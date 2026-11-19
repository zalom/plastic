# frozen_string_literal: true

require_relative "../config"
require_relative "../graph"
require_relative "../graph/settings_database"
require_relative "../graph/knowledge/sync_selection"
require_relative "../graph/knowledge/sync_settings"

module Plastic
  # The one place that joins the settings to the graphs: the settings read and
  # write the machine database through a SettingsDatabase, and the graphs get
  # the sync settings as values. Neither side names the other.
  module Wiring
    Settings = Data.define(:home, :clock) do
      def config(harness: nil) = Wiring.config(home, harness:, clock:)

      def store = Wiring.store(home, clock:)
    end

    REMOVE_AFTER_IMPORT = %w[migrate remove_after_import].freeze
    DAILY_BACKUPS = %w[backup daily].freeze

    def self.config(home, harness: nil, clock: Time) = Config.new(home, harness:, clock:, database: settings_database(home))

    def self.store(home, clock: Time) = Config::Store.new(home, clock:, database: settings_database(home))

    def self.settings(home, clock: Time) = Settings.new(home:, clock:)

    def self.rows(home) = Config::Rows.new(settings_database(home))

    def self.selection(home)
      settings = config(home)
      Graph::Knowledge::SyncSelection.new(types: settings.list("sync.types"), references: settings.flag(%w[sync references], default: false), asked: settings.list("sync.asked"))
    end

    def self.sync(home) = Graph::Knowledge::SyncSettings.new(selection: selection(home), remove_after_import: config(home).flag(REMOVE_AFTER_IMPORT, default: false))

    # Whether the home keeps 24 hours of backups, with a start-of-day and an end-of-day backup of every store.
    def self.daily_backups?(home) = config(home).flag(DAILY_BACKUPS, default: false)

    def self.graphs(home:, store:, session: nil, clock: Time) = Graph.open(home:, store:, session:, clock:, sync: sync(home))

    def self.settings_database(home) = Graph::SettingsDatabase.new(home)
    private_class_method :settings_database
  end
end
