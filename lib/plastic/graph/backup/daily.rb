# frozen_string_literal: true

require_relative "../backup"
require_relative "day"

module Plastic
  module Graph
    module Backup
      # The two backups of the day of every store under stores/ that holds a
      # store database. It never raises: a store whose backup fails is given
      # back with its reason, and the other stores go on.
      class Daily
        # A store whose backup failed, and the first line of why.
        Failure = Data.define(:slug, :reason)

        # `zone` is the offset the days are read in, such as +01:00; nil reads them in the zone of the machine.
        def initialize(home:, now:, zone: nil)
          @stores = File.join(home, "stores")
          @now = now
          @zone = zone
        end

        # The failures of the start-of-day backups the day did not have yet.
        def begin_day = each_store(&:begin_day)

        # The failures of the end-of-day backups, or of the start-of-day ones the day did not have yet.
        def end_session = each_store(&:end_session)

        private

        def slugs
          return [] unless File.directory?(@stores)

          Dir.children(@stores).sort.select { |name| File.directory?(File.join(@stores, name)) }
        end

        def each_store
          slugs.filter_map do |slug|
            yield Day.new(File.join(@stores, slug), slug, now: @now, zone: @zone)
            nil
          rescue => error
            Failure.new(slug, error.message.lines.first.to_s.strip)
          end
        end
      end
    end
  end
end
