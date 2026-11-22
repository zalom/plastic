# frozen_string_literal: true

require "json"
require_relative "../knowledge/spec"
require_relative "../knowledge/stored_output"

module Plastic
  module Graph
    module Work
      # What a worker needs to start one claimed node: the node, the done criterion it serves, its input, and the
      # stored output of each node it needs, the intent's rulings in force and the constraints of its spec, each
      # list kept to LIMIT entries. A harness hands it to the worker, whatever the worker is.
      class Packet
        LIMIT = 20

        # The first needed node that holds output that is not JSON, or nil. A claim asks before it writes a row.
        def self.output_problem(retrieval, node)
          bad = new(retrieval, node, schemas: nil).needed.find { |need| !Knowledge::StoredOutput.valid?(need.output) }
          "node #{bad.id} holds output that is not JSON" if bad
        end

        # `schemas` is the intent's Work::Schemas.
        def initialize(retrieval, node, schemas:)
          @retrieval = retrieval
          @node = node
          @schemas = schemas
        end

        def to_h
          { "node" => { "id" => @node.id, "title" => @node.title, "kind" => @node.kind, "state" => @node.state },
            "criterion" => criterion, "input" => @node.input, "needs" => needs, "schema" => schema,
            "rulings" => kept_rulings, "constraints" => kept_constraints, "omitted" => omitted }
        end

        # The line of the text answer that gives the text of the criterion key.
        def criterion_line = "criterion text: #{criterion.fetch("text")}"

        # The lines of the text answer that give the output of each needed node.
        def need_lines = needs.map { |need| need_line(need) }

        # The lines of the text answer that give each ruling in force and each constraint, then what was left out.
        def rule_lines
          [*kept_rulings.map { |ruling| "ruling: #{ruling.fetch("id")} #{ruling.fetch("text")}" },
           *kept_constraints.map { |text| "constraint: #{text}" }, *omitted_lines]
        end

        # The line of the text answer that names the schema file, or none when the node has no schema.
        def schema_lines = (schema ? ["schema: #{schema}"] : [])

        # The nodes this node needs.
        def needed
          ids = @retrieval.structure.edges(@node.intent_id).select { |edge| edge.kind == "needs" && edge.to == @node.id }.map(&:from)
          ids.filter_map { |id| @retrieval.node(@node.intent_id, id) }
        end

        private

        def schema = @schemas.path(@node.id)

        # Rulings no other ruling supersedes, oldest first.
        def rulings_in_force
          all = @retrieval.rulings(@node.intent_id)
          superseded = all.filter_map(&:supersedes).to_set
          all.reject { |ruling| superseded.include?(ruling.id) }.sort_by { |ruling| ruling.id[/\d+/].to_i }
        end

        # The newest LIMIT rulings in force.
        def kept_rulings = rulings_in_force.last(LIMIT).map { |ruling| { "id" => ruling.id, "text" => ruling.text } }

        def constraints = Knowledge::Spec.new(@retrieval, @node.intent_id).constraints

        def kept_constraints = constraints.first(LIMIT)

        def omitted = { "rulings" => rulings_in_force.size - LIMIT, "constraints" => constraints.size - LIMIT }.select { |_kind, count| count.positive? }

        def omitted_lines
          omitted.map { |kind, count| "omitted: #{count} #{kind}; plastic intent brief #{@node.intent_id} lists them all" }
        end

        def criterion
          key = @node.criterion
          { "key" => key, "text" => Knowledge::Spec.new(@retrieval, @node.intent_id).criteria_by_key.fetch(key, key) }
        end

        def needs = needed.map { |node| { "id" => node.id, "title" => node.title, "output" => node.output && JSON.parse(node.output) } }

        def need_line(need)
          output = need.fetch("output")
          "needs: #{need.fetch("id")} #{output.nil? ? "no output" : JSON.generate(output)}"
        end
      end
    end
  end
end
