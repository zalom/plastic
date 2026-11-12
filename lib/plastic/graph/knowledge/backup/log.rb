# frozen_string_literal: true

require_relative "../backup"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # The backup.log of one backup folder, written one line at a time. A
        # line is on disk when its method returns, and goes to the live sink
        # at the same moment. Every time in it is UTC.
        class Log
          NAME = "backup.log"

          # The one place the shape of a line is decided: a UTC time, the
          # event and its fields as key=value pairs.
          def self.line(time, event, **fields)
            pairs = fields.map { |key, value| "#{key}=#{value.to_s.tr("\n", " ")}" }
            [time.getutc.strftime("%Y-%m-%dT%H:%M:%SZ"), event, *pairs].join(" ")
          end

          def initialize(folder, now:, live: ->(_line) {})
            @path = File.join(folder, NAME)
            @now = now
            @live = live
          end

          def database(name, bytes) = write("database", name:, bytes:, result: "ok")

          def done(databases, bytes) = write("backup", result: "done", databases:, bytes:)

          def failed(reason) = write("backup", result: "failed", reason:)

          private

          def write(event, **fields)
            text = self.class.line(@now, event, **fields)
            File.open(@path, "a") { |file| file.puts(text) }
            @live.call(text)
          end
        end
      end
    end
  end
end
