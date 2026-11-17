# frozen_string_literal: true

require_relative "../backup"
require_relative "../database"
require_relative "databases"
require_relative "integrity"
require_relative "publisher"
require_relative "replacement"
require_relative "target"

module Plastic
  module Graph
    module Backup
      # Replaces the store databases with those of one backup. It refuses
      # while a node claim is live, checks every file first, backs up the
      # current databases, and swaps each file by rename so a failure puts
      # the old ones back.
      class Restorer
        # A node claim of the store is live.
        class Claimed < StandardError; end

        Rejected = Integrity::Rejected

        # One database of a backup would be restored into a store at another schema version.
        class VersionMismatch < StandardError; end

        # The backup is not marked done.
        class NotDone < StandardError; end

        # The backup does not hold a database that was asked for.
        class Missing < StandardError; end

        def self.require_held(timestamp, missing)
          raise Missing, "the backup #{timestamp} does not hold #{missing.first.inspect}" if missing.any?
        end

        def initialize(target, retrieval, now:, sequences: SchemaSequences::SEQUENCES)
          @sequences = sequences
          @target = target
          @retrieval = retrieval
          @now = now
        end

        def claimed? = @retrieval.claimed_nodes.any? { |node| !node.lapsed?(@now) }

        # The database names a restore would replace.
        def held_in(timestamp, names: nil)
          held = held_names(timestamp)
          chosen = Array(names)
          self.class.require_held(timestamp, chosen - held)
          chosen.empty? ? held : chosen
        end

        # Why a restore of this backup is refused now, or nil.
        def refusal(timestamp, databases: nil)
          return "an intent of #{@target.slug} has a node with a live claim" if claimed?

          status = @target.folders.status(timestamp)
          return "the backup #{timestamp} is #{status}; only a done backup restores" unless status == "done"

          mismatch(timestamp) if databases
        end

        # Returns the folder of the safety backup.
        def call(timestamp, databases: nil)
          refuse(timestamp, databases)
          names = verified(timestamp, databases)
          safety = Publisher.new(@target, now: @now, reason: "backup restore").call
          swap(names, timestamp)
          safety.fetch(:name).split("/").last
        end

        private

        def held_names(timestamp) = @target.folders.files(timestamp).map { |file| file.delete_suffix("-#{timestamp}.db") }

        def refuse(timestamp, databases)
          message = refusal(timestamp, databases:)
          raise(error_for(message), message) if message
        end

        def error_for(message)
          return Claimed if claimed?

          message.include?("restore the whole store") ? VersionMismatch : NotDone
        end

        def recorded(timestamp) = @target.folders.report(timestamp).fetch("version", 0).to_i

        def mismatch(timestamp)
          live = live_version
          return if live.nil? || live == recorded(timestamp)

          "the backup #{timestamp} is at schema version #{recorded(timestamp)} and the store is at #{live}; restore the whole store, which migrates it forward"
        end

        # The lowest stamp among the live files that can be read; a damaged file is what a restore repairs, so it does not count.
        def live_version = Databases.all.filter_map { |name| stamp(@target.file(name)) }.min

        def stamp(path)
          return unless File.file?(path)

          SQLite3::Database.open(path, readonly: true) { |database| database.get_first_value("PRAGMA user_version") }
        rescue SQLite3::Exception
          nil
        end

        def source(name, timestamp) = File.join(@target.folders.path(timestamp), "#{name}-#{timestamp}.db")

        def verified(timestamp, databases)
          held_in(timestamp, names: databases).each { |name| Integrity.new(source(name, timestamp), name, version: recorded(timestamp), migrations: @sequences.fetch(:store)).call }
        end

        def swap(names, timestamp)
          Database::ConnectionPool.release(@target.root)
          Replacement.apply_all(names.map { |name| Replacement.new(source(name, timestamp), @target.file(name)) })
        end
      end
    end
  end
end
