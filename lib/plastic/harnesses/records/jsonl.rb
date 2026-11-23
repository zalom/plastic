# frozen_string_literal: true

require "json"
require "time"

module Plastic
  module Harnesses
    module Records
      # The lines of one harness record file, each parsed as JSON. A line that is not JSON is skipped. A file that cannot be
      # read, or that holds text and no JSON line at all, is unreadable and reads as nil, so a caller can say so.
      module Jsonl
        module_function

        def read(path)
          lines = File.readlines(path, chomp: true, encoding: "UTF-8").reject { |line| line.strip.empty? }
          parsed = lines.filter_map { |line| parse(line) }
          parsed unless parsed.empty? && !lines.empty?
        rescue SystemCallError, EncodingError, ArgumentError
          nil
        end

        def parse(line)
          value = JSON.parse(line)
          value if value.is_a?(Hash)
        rescue JSON::ParserError
          nil
        end

        # The time of an entry, or nil when it carries none or an unreadable one.
        def time(entry)
          Time.iso8601(entry["timestamp"].to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
