# frozen_string_literal: true

require "fileutils"
require "sqlite3"
require_relative "../backup"
require_relative "../../lock"
require_relative "../../schema"
require_relative "../../database"
require_relative "folders"
require_relative "publisher"

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

          # A backup file failed its check.
          class Rejected < StandardError; end

          # The backup is not marked done.
          class NotDone < StandardError; end

          # The backup does not hold a database that was asked for.
          class Missing < StandardError; end

          SIDECARS = %w[-journal -wal -shm].freeze

          def initialize(home_db, store_root, slug, now:, session: nil)
            @home_db = home_db
            @root = store_root
            @slug = slug
            @now = now
            @session = session
            @folders = Folders.new(store_root)
          end

          def locked?
            @home_db.rows("SELECT * FROM locks WHERE store = :store", store: @slug).map { |row| Lock.from_h(row) }.any? { |lock| lock.live?(@now) }
          end

          # The database names a restore would replace.
          def held_in(timestamp, names: nil)
            held = @folders.files(timestamp).map { |file| file.delete_suffix("-#{timestamp}.db") }
            missing = (names || []) - held
            raise Missing, "the backup #{timestamp} does not hold #{missing.first.inspect}" if missing.any?

            names || held
          end

          # Why a restore of this backup is refused now, or nil.
          def refusal(timestamp)
            return "an intent of #{@slug} holds a fresh delivery lock" if locked?

            status = @folders.status(timestamp)
            "the backup #{timestamp} is #{status}; only a done backup restores" unless status == "done"
          end

          # Returns the folder of the safety backup.
          def call(timestamp, databases: nil)
            message = refusal(timestamp)
            raise(locked? ? Locked : NotDone, message) if message

            names = held_in(timestamp, names: databases)
            names.each { |held| check(held, timestamp) }
            safety = Publisher.new(@home_db, @root, @slug, now: @now, session: @session).call
            swap(names, timestamp)
            safety.fetch(:name).split("/").last
          end

          private

          def source(name, timestamp) = File.join(@folders.path(timestamp), "#{name}-#{timestamp}.db")

          def target(name) = File.join(@root, "#{name}.db")

          def check(name, timestamp)
            path = source(name, timestamp)
            database = SQLite3::Database.new(path, readonly: true)
            raise Rejected, "#{path} fails the integrity check" unless database.get_first_value("PRAGMA quick_check") == "ok"

            missing = expected_tables(name) - database.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
            raise Rejected, "#{path} lacks the tables #{missing.join(", ")}" unless missing.empty?
          rescue SQLite3::Exception => error
            raise Rejected, "#{path} is not a readable database: #{error.message}"
          ensure
            database&.close
          end

          def expected_tables(name)
            key = Schema.store.find { |candidate| Schema.file(candidate) == "#{name}.db" }
            Schema.databases.fetch(key).last.map(&:to_s)
          end

          def swap(names, timestamp)
            Database::ConnectionPool.release(@root)
            names.each { |name| clear_sidecars(name) }
            done = []
            names.each { |name| done << replace(name, timestamp) }
            done.each { |_target, aside| FileUtils.rm_f(aside) if aside }
          rescue
            put_back(done)
            raise
          end

          def clear_sidecars(name) = SIDECARS.each { |suffix| FileUtils.rm_f("#{target(name)}#{suffix}") }

          def replace(name, timestamp)
            copy = "#{target(name)}.restoring"
            FileUtils.cp(source(name, timestamp), copy)
            aside = File.exist?(target(name)) ? "#{target(name)}.old" : nil
            File.rename(target(name), aside) if aside
            File.rename(copy, target(name))
            [target(name), aside]
          rescue
            FileUtils.rm_f(copy)
            File.rename(aside, target(name)) if aside && !File.exist?(target(name))
            raise
          end

          def put_back(done)
            (done || []).reverse_each do |path, aside|
              aside ? File.rename(aside, path) : FileUtils.rm_f(path)
            end
          end
        end
      end
    end
  end
end
