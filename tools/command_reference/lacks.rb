# frozen_string_literal: true

module CommandReference
  # A workflow with no summary.
  SummaryLack = Data.define(:flow) do
    def self.among(flows) = flows.map { |flow| new(flow) }

    def lacking? = Words.blank?(flow.klass.summary)

    def line = "workflow #{flow.key} needs a summary"
  end

  # An outcome of a code workflow with no because.
  OutcomeLack = Data.define(:flow, :outcome) do
    def self.among(flows) = flows.reject(&:agent?).flat_map { |flow| flow.pairs(flow.outcomes) }.map { |pair| new(*pair) }

    def lacking? = Words.blank?(outcome.because)

    def line = "workflow #{flow.key} outcome #{outcome.name} needs a because"
  end

  # A gate whose reason is a placeholder and which gives no words for it.
  GateLack = Data.define(:flow, :gate) do
    def self.among(flows) = flows.flat_map { |flow| flow.pairs(flow.klass.steps.grep(Plastic::CodeWorkflow::Gate)) }.map { |pair| new(*pair) }

    def lacking? = Words.placeholder?(gate.reason) && Words.blank?(gate.because) && Words.blank?(gate.words)

    def line = "workflow #{flow.key} gate #{gate.reason} needs words"
  end

  # An agent step whose text is a placeholder and which gives no words for it.
  StepLack = Data.define(:flow, :step) do
    def self.among(flows) = flows.flat_map { |flow| flow.pairs(flow.klass.steps.grep(Plastic::AgentWorkflow::Step)) }.map { |pair| new(*pair) }

    def lacking? = Words.placeholder?(step.say) && Words.blank?(step.words)

    def line = "workflow #{flow.key} step #{step.name} needs words"
  end

  # An ending whose because is a placeholder and which gives no words for it.
  EndLack = Data.define(:flow, :outcome) do
    def self.among(flows) = flows.flat_map { |flow| flow.pairs(flow.klass.outcomes) }.map { |pair| new(*pair) }

    def lacking? = Words.placeholder?(outcome.because) && Words.blank?(outcome.words)

    def line = "workflow #{flow.key} outcome #{outcome.name} needs words"
  end
end
