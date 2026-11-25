# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # An old checklist.md: its step lines, each a title and a tick, and the dated rows of its session log table.
          class Checklist
            Item = Data.define(:title, :done)
            Row = Data.define(:date, :items, :notes)

            ITEM = /\A\s*[-*] \[(?<tick>[ xX])\]\s*(?<title>.*)\z/
            ROW = /\A\|\s*(?<date>\d{4}-\d{2}-\d{2})\s*\|(?<rest>.*)\z/

            def initialize(text)
              @text = text
            end

            def items = (@items ||= collect)

            def log_rows = @text.lines.filter_map { |line| row(line.strip) }

            private

            # The lines before a "Session Log" heading; an item line continues on the more indented lines below it.
            def collect
              items = []
              steps.each do |line|
                match = ITEM.match(line)
                match ? items << [match[:title].strip, match[:tick] != " ", indent(line)] : continue(items, line)
              end
              items.map { |title, done, _| Item.new(title:, done:) }
            end

            def steps = @text.lines(chomp: true).take_while { |line| !line.match?(/\A#+\s*Session Log/i) }

            def continue(items, line)
              return if items.empty? || line.strip.empty? || line.start_with?("#", "|") || indent(line) <= items.last[2]

              items.last[0] = "#{items.last[0]} #{line.strip}"
            end

            def indent(line) = line[/\A\s*/].size

            def row(line)
              match = ROW.match(line) or return
              items, notes = match[:rest].sub(/\|\s*\z/, "").split("|", 2)
              Row.new(date: match[:date], items: items.to_s.strip, notes: notes.to_s.strip)
            end
          end
        end
      end
    end
  end
end
