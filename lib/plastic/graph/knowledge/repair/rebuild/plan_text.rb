# frozen_string_literal: true

require_relative "checklist"

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # An old plan.md: its steps, its approach paragraph and the bullets of its Decisions section.
          class PlanText
            LISTED = /\A\s*(?:\d+[.)]|[-*] \[[ xX]\])\s+(?<title>.*)\z/

            def initialize(text)
              @text = text
            end

            def steps
              lines = section("Steps") || @text.lines(chomp: true)
              items(lines.select { |line| line.match?(LISTED) || line.match?(/\A\s+\S/) }).map { |title, done| Checklist::Item.new(title:, done:) }
            end

            def approach
              lines = section("Approach")&.map(&:strip)&.reject(&:empty?)
              lines&.join(" ") unless lines.to_a.empty?
            end

            def decisions = items((section("Decisions") || []).select { |line| line.match?(/\A\s*[-*]\s/) || line.match?(/\A\s+\S/) }, bullet: true).map(&:first)

            private

            # The lines under the heading `name`, up to the next heading, or nil when there is none.
            def section(name)
              lines = @text.lines(chomp: true)
              from = lines.index { |line| line.match?(/\A##+\s*#{name}\b/i) } or return
              rest = lines.drop(from + 1)
              rest.take_while { |line| !line.start_with?("#") }
            end

            def items(lines, bullet: false)
              lines.each_with_object([]) do |line, items|
                if (title = start(line, bullet))
                  items << [title, line.match?(/\[[xX]\]/)]
                elsif items.any?
                  items.last[0] = "#{items.last[0]} #{line.strip}"
                end
              end
            end

            def start(line, bullet)
              return line.sub(/\A\s*[-*]\s+/, "").strip if bullet && line.match?(/\A\s*[-*]\s/)

              LISTED.match(line)&.[](:title)&.strip
            end
          end
        end
      end
    end
  end
end
