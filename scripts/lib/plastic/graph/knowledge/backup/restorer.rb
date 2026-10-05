# frozen_string_literal: true

require_relative "../backup"
require_relative "../../lock"
require_relative "../../database"
require_relative "integrity"
require_relative "publisher"
require_relative "replacement"
require_relative "target"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Replaces the store databases with those of one backup. It refuses
        # while a delivery lock is fresh, checks every file first, backs up the
        # current databases, and swaps each file by rename so a failure puts
        # the old ones back.
        class Restorer
          # A delivery lock of the store is fresh.
          class Locked < StandardError; end

          Rejected = Integrity::Rejected

          # The backup is not marked done.
          class NotDone < StandardError; end

          # The backup does not hold a database that was asked for.
          class Missing < StandardError; end

          def self.require_held(timestamp, missing)
            raise Missing, "the backup #{timestamp} does not hold #{missing.first.inspect}" if missing.any?
          end

          def initialize(home_db, store_root, slug, now:, session: nil)
            @target = Target.new(home_db, store_root, slug, session)
            @now = now
          end

          def locked?
            rows = @target.home_db.rows("SELECT * FROM locks WHERE store = :store", store: @target.slug)
            rows.map { |row| Lock.from_h(row) }.any? { |lock| lock.live?(@now) }
          end

          # The database names a restore would replace.
          def held_in(timestamp, names: nil)
            held = held_names(timestamp)
            chosen = Array(names)
            self.class.require_held(timestamp, chosen - held)
            chosen.empty? ? held : chosen
          end

          # Why a restore of this backup is refused now, or nil.
          def refusal(timestamp)
            return "an intent of #{@target.slug} holds a fresh delivery lock" if locked?

            status = @target.folders.status(timestamp)
            "the backup #{timestamp} is #{status}; only a done backup restores" unless status == "done"
          end

          # Returns the folder of the safety backup.
          def call(timestamp, databases: nil)
            refuse(timestamp)
            names = verified(timestamp, databases)
            safety = Publisher.new(@target, now: @now).call
            swap(names, timestamp)
            safety.fetch(:name).split("/").last
          end

          private

          def held_names(timestamp) = @target.folders.files(timestamp).map { |file| file.delete_suffix("-#{timestamp}.db") }

          def refuse(timestamp)
            message = refusal(timestamp)
            raise(locked? ? Locked : NotDone, message) if message
          end

          def source(name, timestamp) = File.join(@target.folders.path(timestamp), "#{name}-#{timestamp}.db")

          def verified(timestamp, databases)
            held_in(timestamp, names: databases).each { |name| Integrity.new(source(name, timestamp), name).call }
          end

          def swap(names, timestamp)
            Database::ConnectionPool.release(@target.root)
            Replacement.apply_all(names.map { |name| Replacement.new(source(name, timestamp), @target.file(name)) })
          end
        end
      end
    end
  end
end
