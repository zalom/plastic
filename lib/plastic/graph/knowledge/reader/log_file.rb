# frozen_string_literal: true

require_relative "../../rows/log_line"
require_relative "../../rows/savepoint"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # The lines of a work.log, or of an old savepoint.md, read into work log rows.
        class LogFile
          def initialize(text, intent_id)
            @text = text
            @intent_id = intent_id
          end

          # The rows of the file replace the rows the intent held.
          def work_log(batch)
            batch.remove(:work_log, intent_id: @intent_id)
            batch.put_all(:work_log, lines.each_with_index.map { |line, index| log_row(line, index) })
          end

          # The lines of the old file that the log does not hold yet go after the last logged line.
          def savepoint(batch, logged)
            texts = logged.map(&:text)
            added = lines.map { |line| old_row(line) }.reject { |row| texts.include?(row[:text]) }
            batch.put_all(:work_log, added.each_with_index.map { |row, index| { **row, position: logged.map(&:position).max.to_i + index + 1 } })
          end

          private

          def lines = @text.lines(chomp: true).reject { |line| line.strip.empty? }

          def log_row(line, index) = { intent_id: @intent_id, position: index + 1, **Work::LogLine.parse(line) }

          def old_row(line)
            at, said = Work::Savepoint.parse(line)
            { intent_id: @intent_id, at:, kind: "noted", text: said }
          end
        end
      end
    end
  end
end
