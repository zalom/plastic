# frozen_string_literal: true

module CommandReference
  module Markdown
    # The events of one call, told in the order they happen: the command's own call, then each workflow row by row.
    class Events
      def initialize(page, links)
        @page = page
        @links = links
        @flows = page.flows
      end

      def lines = ["## The events of one call", "", *body, *(Engines.new(@page).lines if @flows.any?)]

      private

      def body
        return OwnCallEvents.new(@page, @links).lines if @flows.empty?
        return single if @flows.size == 1 && !@page.own_call

        several
      end

      def single
        flow = @flows.first
        ["The call starts the workflow `#{flow.path}`, in #{@links.code(flow.file, flow.line)}.", "", *FlowEvents.new(flow, @page, @links).lines]
      end

      def several
        [*(overview if @flows.size > 1), *own, *@flows.flat_map { |flow| subsection(flow) }]
      end

      def overview
        ["![The workflows of plastic #{@page.words}](workflows.svg)", "", "| Workflow | Kind | Code |", "| --- | --- | --- |",
          *@flows.map { |flow| FlowRow.new(flow, @links).to_s }, ""]
      end

      def own = @page.own_call ? OwnCallEvents.new(@page, @links).before_workflows : []

      def subsection(flow)
        ["### #{flow.path}", "", "The #{flow.lane} workflow `:#{flow.key}`, in #{@links.code(flow.file, flow.line)}.", "", *FlowEvents.new(flow, @page, @links).lines]
      end
    end

    # The call method a command writes for itself, told before the workflows or, without workflows, step by step.
    class OwnCallEvents
      def initialize(page, links)
        @page = page
        @links = links
        @own = page.own_call
      end

      def lines
        ["![The call of plastic #{@page.words}](call.svg)", "", "#{opening}:", "", *code, "Its steps run in this order:", "", *CallSteps.new(@own, @links).lines, ""]
      end

      def before_workflows
        entry = @page.flow(@page.entry)
        ["### The command's own call", "",
          "The command's own `call`, at #{@links.at(@own)}, runs first, then starts the workflow [#{entry.path}](##{entry.anchor}).", "", *code]
      end

      private

      def opening
        name = (@page.kind == :hook) ? "The hook's `respond`" : "The command's `call`"
        "#{name}, at #{@links.at(@own)}"
      end

      def code = ["```ruby", *@own.code, "```", "", *check_call]

      def check_call
        check = @own.check
        check ? ["The command's own `check_call`, at #{@links.at(check)}, runs inside it:", "", "```ruby", *check.code, "```", ""] : []
      end
    end

    # One workflow told row by row: its picture, its numbered rows and outcomes, what the agent is told and what it sets.
    class FlowEvents
      def initialize(flow, page, links)
        @flow = flow
        @page = page
        @links = links
      end

      def lines = [*Prose.lines(@flow.comment), *picture, "Its rows run in this order:", "", *items, "", *says, *facts, *handoff]

      private

      def picture = ["![How #{@flow.path} runs: its steps, where it stops, and its outcomes](#{@flow.key}.svg)", ""]

      def items
        entries = [*@flow.rows.map { |row| [RowItem.new(row), row] }, *@flow.outcomes.map { |outcome| [OutcomeItem.new(outcome, @flow, @page), outcome] }]
        entries.each_with_index.map { |(item, place), at| "#{at + 1}. #{item} #{@links.code(place.file, place.line)}" }
      end

      def says = @flow.rows.reject { |row| row.say.to_s.empty? }.flat_map(&:saying)

      def facts
        names = @flow.facts.map { |fact| "`#{fact}`" }.join(", ")
        names.empty? ? [] : ["It sets #{names}.", ""]
      end

      def handoff
        outcome = @flow.outcomes.find { |each| each.name == :handoff }
        outcome ? ["#{hands_off(outcome)} #{resume}", ""] : []
      end

      def hands_off(outcome)
        offer = (found = Array(outcome.offers).first) ? "offers next: #{Words.plain(found)}" : Endings::NONE
        "While a step is left, the call hands off with exit #{outcome.exit_code} from `:handoff`: it prints the `say:` text of each failing step and #{offer}."
      end

      def resume
        return "The command writes, so the call keeps its routine run row in local.db. The next call loads its facts, restarts at the first workflow and skips each step whose `done:` check holds." if @page.klass.writes.any?

        "The command writes nothing, so the call keeps no routine run row. The next call starts fresh and checks the steps again."
      end
    end
  end
end
