# frozen_string_literal: true

require_relative "../../../clock"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # The entries of an old revisions.md. A heading `## Revision vN - DATE` opens an entry whose text is the lines below
        # it, made one line; a heading inside a fenced block is text. Before the first heading, a title line is dropped and
        # each dated bullet `- DATE text` is an entry of its own. A time with no zone reads in `zone`, an offset such as
        # +02:00, or else in the zone of the machine, where the owner wrote it; each entry keeps its time in UTC. A file with
        # no entry, or with other text before its first heading, is not readable.
        class Revisions
          Entry = Data.define(:label, :at, :text)

          HEADING = /\A## Revision (?<label>v[\w.]+) - (?<date>\d{4}-\d\d-\d\d)(?:-(?<time>\d\d:\d\d))?\s*\z/
          BULLET = /\A- (?<date>\d{4}-\d\d-\d\d)(?:T(?<time>\d\d:\d\d)(?::\d\d)?(?<zone>Z|[+-]\d\d:\d\d)?)?\s+(?<text>\S.*)\z/
          TITLE = /\A# /
          FENCE = /\A\s*```/

          def initialize(text, zone: nil)
            @lines = text.lines(chomp: true)
            @zone = zone
          end

          def entries = (@entries ||= [*bullets, *sections])

          def readable? = !entries.empty? && stray.empty?

          private

          def preamble = @lines.take_while { |line| !line.match?(HEADING) }

          def stray = preamble.reject { |line| line.strip.empty? || line.match?(TITLE) || line.match?(BULLET) }

          def bullets
            preamble.filter_map { |line| line.match(BULLET) }.each_with_index.map do |found, index|
              Entry.new(label: "entry #{index + 1}", at: time(found), text: found[:text].strip)
            end
          end

          def sections = section_lines.map { |heading, body| Entry.new(label: heading[:label], at: time(heading), text: one_line(body)) }

          # Each heading with the lines below it, up to the next heading outside a fenced block.
          def section_lines
            fenced = false
            @lines.drop(preamble.size).each_with_object([]) do |line, found|
              heading = line.match(HEADING) unless fenced
              fenced = !fenced if line.match?(FENCE)
              heading ? found << [heading, []] : found.last.last << line
            end
          end

          def one_line(body) = body.join("\n").gsub(/\s*\R\s*/, " ").strip

          def time(found)
            year, month, day = found[:date].split("-").map(&:to_i)
            hour, minute = (found[:time] || "00:00").split(":").map(&:to_i)
            Plastic.timestamp(Time.new(year, month, day, hour, minute, 0, zone_of(found)))
          end

          def zone_of(found) = (found.names.include?("zone") && found[:zone]) || @zone
        end
      end
    end
  end
end
