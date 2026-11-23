# frozen_string_literal: true

require_relative "../backup"
require_relative "../database"
require_relative "../schema/gate"
require_relative "../schema/state"
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

        def initialize(target, retrieval, now:, migrations: MIGRATIONS)
          @target = target
          @retrieval = retrieval
          @now = now
          @migrations = migrations
        end

        # A store file that cannot be read holds no claim a restore could honour: a restore is what repairs it.
        def claimed?
          @retrieval.claimed_nodes.any? { |node| !node.lapsed?(@now) }
        rescue Database::Error
          false
        end

        # The database names a restore would replace.
        def held_in(timestamp, names: nil)
          held = held_files(timestamp)
          chosen = Array(names)
          self.class.require_held(timestamp, chosen - held)
          chosen.empty? ? held : chosen
        end

        # Why a restore of this backup is refused now, or nil.
        def refusal(timestamp, databases: nil)
          return "an intent of #{@target.slug} has a node with a live claim" if claimed?

          status = @target.folders.status(timestamp)
          return "the backup #{timestamp} is #{status}; only a done backup restores" unless status == "done"

          databases&.then { mismatch(timestamp) }
        end

        # Returns the folder of the safety backup.
        def call(timestamp, databases: nil)
          held = held_in(timestamp, names: databases)
          message = refusal(timestamp, databases:)
          raise(error_for(message), message) if message

          names = verified(timestamp, held)
          safety = Publisher.new(@target, now: @now, reason: "backup restore").call
          swap(names.map { |name| replacement(name, timestamp) })
          safety.fetch(:name).split("/").last
        end

        private

        # The database names the folder holds; a done folder that holds none has nothing to restore.
        def held_files(timestamp)
          folders = @target.folders
          held = folders.files(timestamp).map { |file| file.delete_suffix("-#{timestamp}.db") }
          raise Missing, "the backup #{timestamp} holds no database files" if held.empty? && folders.status(timestamp) == "done"

          held
        end

        def error_for(message)
          return Claimed if claimed?

          message.include?("restore the whole store") ? VersionMismatch : NotDone
        end

        def recorded(timestamp) = @target.folders.report(timestamp).fetch("version", 0).to_i

        def mismatch(timestamp)
          live = live_version
          recorded = @migrations.number(:store, recorded(timestamp))
          return if live.nil? || live == recorded

          "the backup #{timestamp} is at schema version #{recorded} and the store is at #{live}; restore the whole store, which migrates it forward"
        end

        # The version the live knowledge database records; a damaged file is what a restore repairs, so it does not count.
        def live_version
          path = @target.file("knowledge_graph")
          SchemaState.of_file(path, :store).number if File.file?(path)
        rescue SQLite3::Exception
          nil
        end

        def source(name, timestamp) = File.join(@target.folders.path(timestamp), "#{name}-#{timestamp}.db")

        def verified(timestamp, names)
          names.each { |name| Integrity.new(source(name, timestamp), name, version: recorded(timestamp), migrations: @migrations).call }
        end

        def replacement(name, timestamp) = Replacement.new(source(name, timestamp), @target.file(name))

        def swap(replacements)
          Database::ConnectionPool.release(@target.root)
          Replacement.apply_all(replacements)
        end
      end
    end
  end
end
