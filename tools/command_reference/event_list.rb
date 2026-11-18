# frozen_string_literal: true

module CommandReference
  STOP_HEADS = { failure: "STOPS", refusal: "STOPS", handoff: "HANDS OFF", end: "ENDS" }.freeze
  LANE_LABELS = { code: "Code Workflow", agent: "Agent Workflow", command: "Command", hook: "Hook" }.freeze

  # A way the call stops beside an event: a failure, a refusal, a hand off or an end.
  Stop = Data.define(:kind, :exit_code, :text, :next_line) do
    def look = [kind, tag]

    def tag = "#{STOP_HEADS.fetch(kind)}, EXIT #{exit_code}"

    def words = [text, next_line].compact

    def self.next_line(offers) = Array(offers).first&.then { |text| "next: #{Words.angled(text)}" }
  end

  # One box of the events of a call: a read, a step or an agent step, with the stops beside it.
  Event = Data.define(:number, :lane, :text, :say, :stops, :way, :joined) do
    def label = LANE_LABELS.fetch(lane)

    def agent? = lane == :agent

    def said? = !say.to_s.strip.empty?

    def say_row = "| #{number} | #{Words.shown(say)} |"
  end

  # The stop a gate makes: a refusal or a failure, in the words of its reason.
  GateStop = Data.define(:gate) do
    def stop = Stop.new(kind, (kind == :refusal) ? 3 : 1, Words.sentence(words), Stop.next_line(gate.offers))

    def kind = (gate.stops == :refusal) ? :refusal : :failure

    def words
      reason = gate.reason
      gate.because || (Words.placeholder?(reason) ? gate.words : reason)
    end
  end

  # The boxes of one workflow before they are numbered, each with the stops beside it.
  class Drafts
    CHECK = "Check that the call can go on."

    def initialize
      @items = []
    end

    def add(row)
      @items << row.draft
    end

    def hang_last(stop)
      @items << { lane: :code, text: CHECK, say: nil, stops: [] } if @items.empty?
      @items.last[:stops] << stop
    end

    def hang_end(outcome, flow_key, stop)
      holder = outcome.holder_among(@items, flow_key)
      holder ? holder[:stops] << stop : hang_last(stop)
    end

    def events = @items.map { |draft| Event.new(nil, *draft.values_at(:lane, :text, :say, :stops), nil, true) }
  end

  # The stops and the end of one workflow, in the words a person reads.
  class FlowStops
    def initialize(flow)
      @flow = flow
    end

    def events
      drafts = stepped
      shown.each { |outcome| drafts.hang_end(outcome, @flow.key, end_stop(outcome)) }
      drafts.events
    end

    def gates = @flow.klass.steps.grep(Plastic::CodeWorkflow::Gate).map { |gate| GateStop.new(gate).stop }

    def closing = shown.map { |outcome| end_stop(outcome) }

    private

    def shown = @flow.outcomes.select(&:shown?)

    def stepped
      @flow.klass.steps.zip(@flow.rows).each_with_object(Drafts.new) do |(step, row), drafts|
        row.gate? ? drafts.hang_last(GateStop.new(step).stop) : drafts.add(row)
      end
    end

    def end_stop(outcome) = outcome.stop_in(@flow)
  end

  # The numbered events of a whole call, in the order the call runs them.
  class EventList
    def initialize(page)
      @page = page
    end

    def events = @events ||= listed.each_with_index.map { |event, at| event.with(number: at + 1) }

    private

    def listed
      flows = @page.flows
      flows.empty? ? [call_event] : flows.flat_map { |flow| start_way(flow, FlowStops.new(flow).events) }
    end

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

    def previous_of(flow) = @page.before(flow)

    def call_event
      Event.new(nil, (@page.kind == :hook) ? :hook : :command, Words.sentence(@page.summary), nil, call_stops, nil, true)
    end

    def call_stops = @page.endings.map(&:stop).uniq
  end
end
