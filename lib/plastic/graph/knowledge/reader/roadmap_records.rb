# frozen_string_literal: true

require_relative "../roadmap/form"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # The labeled records of a roadmap file in form 2: the head, and the batches, items, edges and log lines
        # in the order the file lists them. A value is the text after its label, unescaped.
        class RoadmapRecords
          Form = Roadmap::Form
          RECORD_STARTS = { "- edge" => :edges, "- log" => :log }.freeze

          # A value that is empty is no value.
          def self.blank(value) = (value && value.empty?) ? nil : value

          attr_reader :head

          def initialize(lines)
            @records = Hash.new { |hash, key| hash[key] = [] }
            @head = {}
            @section = :head
            @target = @head
            lines.each { |line| read_line(line) }
          end

          def of(kind) = (kind == :head) ? [@head] : @records[kind]

          private

          def read_line(line)
            return heading(line) if line.start_with?("## ")
            return start(:items) if @section == :batches && line.start_with?("- [")
            return start(@section) if RECORD_STARTS[line] == @section

            labeled(line)
          end

          def heading(line)
            batch = line[/\A## Batch (\d+)(?::|\z)/, 1]
            @section = batch ? :batches : line.delete_prefix("## ").downcase.to_sym
            @section = :edges if @section == :graph
            start(:batches, position: batch) if batch
          end

          def start(kind, **fields)
            @target = fields.transform_keys(&:to_s).merge("batch" => @records[:batches].last&.fetch("position", nil))
            @records[kind] << @target
          end

          def labeled(line)
            key, value = Form::LABELED.match(line)&.captures
            @target[key] = Form.unescape(value.to_s) if key
          end
        end
      end
    end
  end
end
