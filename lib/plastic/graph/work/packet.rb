# frozen_string_literal: true

require "json"
require_relative "../knowledge/spec"
require_relative "packet_rules"
require_relative "../knowledge/stored_output"

module Plastic
  module Graph
    module Work
      # What a worker needs to start one claimed node: the node, the done criterion it serves, its input paths, and the
      # stored output of each node it needs, and the rules of the intent: its rulings in force and the constraints
      # of its spec. A harness hands it to the worker, whatever the worker is.
      class Packet
        # The first needed node that holds output that is not JSON, or nil. A claim asks before it writes a row.
        def self.output_problem(retrieval, node)
          bad = new(retrieval, node, schemas: nil).needed.find { |need| !Knowledge::StoredOutput.valid?(need.output) }
          "node #{bad.id} holds output that is not JSON" if bad
        end

        # The line of the text answer that gives one need: its node id and its output.
        def self.need_line(need)
          output = need.fetch("output")
          "needs: #{need.fetch("id")} #{output.nil? ? "no output" : JSON.generate(output)}"
        end

        # `schemas` is the intent's Work::Schemas.
        def initialize(retrieval, node, schemas:)
          @retrieval = retrieval
          @node = node
          @schemas = schemas
        end

        def to_h
          { "node" => { "id" => @node.id, "title" => @node.title, "kind" => @node.kind, "state" => @node.state },
            "criterion" => criterion, "inputs" => inputs, "needs" => needs, "schema" => schema, "output" => output_text,
            "rulings" => rules.rulings, "constraints" => rules.constraints, "omitted" => rules.omitted }
        end

        # The line of the text answer that gives the text of the criterion key.
        def criterion_line = "criterion text: #{criterion.fetch("text")}"

        # The input paths of the node in the order given; none when it reads no file.
        def inputs = @retrieval.structure.node_inputs(@node.intent_id).select { |row| row.node_id == @node.id }.map(&:path)

        # The lines of the text answer that give the input paths, one line each.
        def input_lines = inputs.map { |path| "input: #{path}" }

        # The lines of the text answer that give the output of each needed node.
        def need_lines = needs.map { |need| Packet.need_line(need) }

        # The lines of the text answer after the inputs: the needs, the rulings and constraints, the schema.
        def answer_lines = [*need_lines, *rule_lines, *schema_lines, "output: #{output_text}"]

        # The lines of the text answer that give the rulings in force, the constraints and what was left out.
        def rule_lines = rules.lines

        # The line of the text answer that names the schema file, or none when the node has no schema.
        def schema_lines = (schema ? ["schema: #{schema}"] : [])

        # The nodes this node needs.
        def needed
          intent = @node.intent_id
          ids = @retrieval.structure.edges(intent).select { |edge| edge.kind == "needs" && edge.to == @node.id }.map(&:from)
          ids.filter_map { |id| @retrieval.node(intent, id) }
        end

        private

        def output_text = "a JSON file, given with plastic node done #{@node.intent_id} #{@node.id} TEXT --output PATH"

        def schema = @schemas.path(@node.id)

        def rules = @rules ||= PacketRules.new(@retrieval, @node.intent_id)

        def criterion
          key = @node.criterion
          { "key" => key, "text" => Knowledge::Spec.new(@retrieval, @node.intent_id).criteria_by_key.fetch(key, key) }
        end

        def needs = needed.map(&:to_h).map { |row| row.slice(:id, :title).transform_keys(&:to_s).merge("output" => Knowledge::StoredOutput.parse(row[:output])) }
      end
    end
  end
end
