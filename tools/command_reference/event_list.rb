# frozen_string_literal: true

module CommandReference
  STOP_HEADS = { failure: "STOPS", refusal: "STOPS", handoff: "HANDS OFF", end: "ENDS" }.freeze
  LANE_LABELS = { code: "Code Workflow", agent: "Agent Workflow", command: "Command", hook: "Hook" }.freeze

  # A way the call stops beside an event: a failure, a refusal, a hand off or an end.
  Stop = Data.define(:kind, :exit_code, :text, :next_line) do
    def tag = "#{STOP_HEADS.fetch(kind)}, EXIT #{exit_code}"

    def words = [text, next_line].compact
  end

  # One box of the events of a call: a read, a step or an agent step, with the stops beside it.
  Event = Data.define(:number, :lane, :text, :say, :stops, :way, :joined) do
    def label = LANE_LABELS.fetch(lane)

    def agent? = lane == :agent
  end

  # The stops and the end of one workflow, in the words a person reads.
  class FlowStops
    CHECK = "Check that the call can go on."

    def initialize(flow)
      @flow = flow
    end

    def events
      drafts = stepped
      shown.each { |outcome| hang(drafts, end_stop(outcome), holder_of(drafts, outcome)) }
      drafts.map { |draft| Event.new(nil, *draft.values_at(:lane, :text, :say, :stops), nil, true) }
    end

    def gates = @flow.klass.steps.grep(Plastic::CodeWorkflow::Gate).map { |gate| gate_stop(gate) }

    def closing = shown.map { |outcome| end_stop(outcome) }

    private

    def shown = @flow.outcomes.select { |outcome| outcome.ends? && !outcome.unreachable }

    def stepped
      @flow.klass.steps.zip(@flow.rows).each_with_object([]) { |(step, row), drafts| row.gate? ? hang(drafts, gate_stop(step)) : drafts << draft(row) }
    end

    def draft(row) = { lane: (row.kind == :agent) ? :agent : :code, text: Words.sentence(row.name), say: row.say, stops: [] }

    def hang(drafts, stop, holder = nil)
      drafts << { lane: :code, text: CHECK, say: nil, stops: [] } if drafts.empty?
      (holder || drafts.last)[:stops] << stop
    end

    # The box of the step an outcome names with found_by:, nil when it names none.
    def holder_of(drafts, outcome)
      return unless outcome.found_by

      drafts.find { |draft| draft[:text] == Words.sentence(outcome.found_by) } ||
        raise(ArgumentError, "workflow #{@flow.key} outcome #{outcome.name} is found_by #{outcome.found_by}, which is no step of the workflow")
    end

    def gate_stop(gate)
      kind = (gate.stops == :refusal) ? :refusal : :failure
      Stop.new(kind, (kind == :refusal) ? 3 : 1, Words.sentence(gate_words(gate)), next_line(gate.offers))
    end

    def gate_words(gate) = gate.because || (gate.reason.match?(PageWords::PLACEHOLDER) ? gate.words : gate.reason)

    def end_stop(outcome)
      kind = (@flow.agent? && outcome.name == :handoff && outcome.exit_code != 0) ? :handoff : :end
      Stop.new(kind, outcome.exit_code, Words.sentence(outcome.because), next_line(outcome.offers))
    end

    def next_line(offers) = Array(offers).first&.then { |text| "next: #{Words.angled(text)}" }
  end

  # The numbered events of a whole call, in the order the call runs them.
  class EventList
    def initialize(page)
      @page = page
    end

    def events = @events ||= listed.each_with_index.map { |event, at| event.with(number: at + 1) }

    private

    def listed = @page.flows.empty? ? [call_event] : @page.flows.flat_map { |flow| start_way(flow, FlowStops.new(flow).events) }

    def start_way(flow, events)
      first, *rest = events
      [first.with(way: way_of(flow), joined: joined?(flow)), *rest]
    end

    def way_of(flow)
      reason = Reasons.new(@page).into(flow.key)
      (joined?(flow) || reason.empty?) ? nil : "When #{reason}:"
    end

    def joined?(flow)
      sources = @page.edges.select { |edge| edge.to == flow.key }.map(&:from).uniq
      sources.empty? || (sources == [previous_of(flow)] && single_way_on?(sources.first))
    end

    def single_way_on?(key) = @page.edges.select { |edge| edge.from == key }.map(&:to).uniq.size == 1

    def previous_of(flow) = @page.flows.fetch(@page.flows.index(flow) - 1).key

    def call_event
      Event.new(nil, (@page.kind == :hook) ? :hook : :command, Words.sentence(@page.summary), nil, call_stops, nil, true)
    end

    def call_stops = @page.endings.map { |ending| call_stop(ending) }.uniq

    def call_stop(ending)
      kind = { 0 => :end, 3 => :refusal }.fetch(ending.exit_code, :failure)
      Stop.new(kind, ending.exit_code, Words.sentence(ending.text), call_next(ending.next_text))
    end

    def call_next(text) = [Endings::NONE, Endings::RUNTIME].include?(text) ? nil : "next: #{Words.angled(text)}"
  end
end
