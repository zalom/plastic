# frozen_string_literal: true

require_relative "checklist"
require_relative "plan_text"
require_relative "brief"
require_relative "generated"
require_relative "steps"
require_relative "../../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # The records one old intent folder gives: the nodes of its steps, the work log lines of its session log, and the
          # rulings of its plan. `files` maps each file of the folder, by its path in the folder, to its text; `status`
          # is the state of the intent; `held` is the text of the rulings and the spec the store already holds, so a
          # decision it holds is not ruled again. A generated file gives no record.
          class Intent
            Line = Data.define(:at, :text)

            def initialize(dir, files, status:, held: "", graphed: false)
              @dir = dir
              @files = files.reject { |_, text| Generated.call(text) }
              @status = status
              @held = held
              @graphed = graphed
            end

            attr_reader :dir

            def intent_id = SyncSelection.intent_of(dir)

            # What the rebuild gives, in words: the nodes, packets, findings, work log lines and rulings.
            def summary
              counts = [[nodes.size, "node", "nodes"], [nodes.count(&:packet), "packet", "packets"], [nodes.count(&:findings), "finding", "findings"],
                [lines.size, "work log line", "work log lines"], [rulings.size, "ruling", "rulings"]]
              counts.map { |count, one, many| "#{count} #{(count == 1) ? one : many}" }.join(", ")
            end

            # An intent that already has graph nodes keeps them; its old steps and briefs give none.
            def nodes = @graphed ? [] : Steps.new(items, briefs, @status).call

            def lines = rows.map { |row| Line.new(at: "#{row.date}T00:00:00Z", text: "Session log of #{[row.date, row.label].reject(&:empty?).join(" ")}: #{[row.items, row.notes].reject(&:empty?).join(". ")}") }

            def rulings = [approach, *decisions.reject { |text| held?(text) }].compact

            # The paths in the folder of the files whose data the rebuild takes in.
            def rebuilt = @files.keys.sort

            private

            def checklist = (@checklist ||= Checklist.new(@files.fetch(Layout.legacy_name(:checklist), "")))

            def plan = (@plan ||= PlanText.new(@files.fetch(Layout.legacy_name(:plan), "")))

            def items = checklist.items.empty? ? plan.steps : checklist.items

            def briefs = @files.select { |rel, _| rel.start_with?("actions/") }.map { |rel, text| Brief.new(rel, text) }

            def rows = checklist.log_rows

            def approach = plan.approach && "Approach: #{plan.approach}"

            def decisions = plan.decisions

            def held?(text) = squeeze(@held).include?(squeeze(text))

            def squeeze(text) = text.gsub(/\s+/, " ")
          end
        end
      end
    end
  end
end
