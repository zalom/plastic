# frozen_string_literal: true

module CommandReference
  # One outcome line of a workflow.
  Outcome = Data.define(:name, :check, :fallback, :offers, :because, :to, :exit_code, :file, :line, :found_by, :unreachable) do
    def initialize(found_by: nil, unreachable: nil, **rest) = super

    def ends? = to == :noop

    def exit_words = (name == :handoff) ? "hands off, exit #{exit_code}" : "finishes, exit 0"

    def next_words = Array(offers).map { |each| "next: #{each}" }.first || Endings::NONE

    def shown? = ends? && !unreachable

    def stop_in(flow) = stop((flow.agent? && handoff_failure?) ? :handoff : :end)

    def handoff_failure? = name == :handoff && exit_code != 0

    def stop(kind) = Stop.new(kind, exit_code, Words.sentence(because), Stop.next_line(offers))

    def holder_among(drafts, flow_key)
      step = found_by
      return unless step

      drafts.find { |draft| draft[:text] == Words.sentence(step) } ||
        raise(ArgumentError, "workflow #{flow_key} outcome #{name} is found_by #{step}, which is no step of the workflow")
    end

    def ending(kind) = Ending.new(kind, exit_code, offers || Endings::NONE, because, file, line)
  end
end
