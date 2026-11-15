# frozen_string_literal: true

module CommandReference
  # The words one page lacks, one line each, every line led by the page's words.
  class PageWords
    PLACEHOLDER = /\A%\{\w+\}\z/

    def initialize(page)
      @page = page
      @flows = page.flows
    end

    def lines = [*summary_lines, *outcome_lines, *gate_lines, *placeholder_lines, *changes_lines].map { |line| "#{@page.words}: #{line}" }

    private

    def many? = @flows.size > 1

    def blank?(text) = text.to_s.strip.empty?

    def summary_lines
      return [] unless many?

      @flows.select { |flow| blank?(flow.klass.summary) }.map { |flow| "workflow #{flow.key} needs a summary" }
    end

    def outcome_lines
      return [] unless many?

      @flows.reject(&:agent?).flat_map do |flow|
        flow.outcomes.select { |outcome| blank?(outcome.because) }.map { |outcome| "workflow #{flow.key} outcome #{outcome.name} needs a because" }
      end
    end

    def gate_lines
      gates.select { |_flow, gate| gate.reason.match?(PLACEHOLDER) && blank?(gate.because) && blank?(gate.stops_when) }
        .map { |flow, gate| "workflow #{flow.key} gate #{gate.reason} needs a stops_when" }
    end

    def placeholder_lines = [*say_lines, *ends_lines]

    def say_lines
      agent_steps.select { |_flow, step| step.say.match?(PLACEHOLDER) && blank?(step.gets) }
        .map { |flow, step| "workflow #{flow.key} step #{step.name} needs a gets" }
    end

    def ends_lines
      @flows.flat_map do |flow|
        flow.klass.outcomes.select { |outcome| outcome.because.to_s.match?(PLACEHOLDER) && blank?(outcome.ends_when) }
          .map { |outcome| "workflow #{flow.key} outcome #{outcome.name} needs an ends_when" }
      end
    end

    def agent_steps = @flows.flat_map { |flow| flow.klass.steps.grep(Plastic::AgentWorkflow::Step).map { |step| [flow, step] } }

    def gates = @flows.flat_map { |flow| flow.klass.steps.grep(Plastic::CodeWorkflow::Gate).map { |gate| [flow, gate] } }

    def changes_lines = [*empty_lines, *unwritten_lines, *place_lines]

    def empty_lines = (@flows.empty? && @page.klass.changes.nil?) ? ["needs changes, the words of what a call changes, or an empty hash"] : []

    def unwritten_lines
      (@page.klass.writes - changed.keys).map { |graph| "writes #{graph} but has no change in words at #{graph}; add changes" }
    end

    def place_lines = changed.keys.reject { |key| Places.known?(key) }.map { |key| "change at #{key} is no known place" }

    def changed
      @changed ||= [*@flows.flat_map { |flow| flow.klass.steps.grep(Plastic::CodeWorkflow::Step).map(&:changes) }, @page.klass.changes]
        .compact.reduce({}) { |all, each| all.merge(each) }
    end
  end
end
