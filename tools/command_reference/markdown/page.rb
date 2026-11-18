# frozen_string_literal: true

module CommandReference
  module Markdown
    # The README of one command: what it is, its two drawings, what it changes and what its agent steps print.
    class Page
      GOES_WITH_THE_STORE = "Goes with the store: the files of the store carry the change, and `plastic sync up` rebuilds it on another machine. " \
        "The database files themselves stay on this machine."

      def initialize(page, base: "../../../../")
        @page = page
        @links = Links.new(base)
      end

      def to_s = [*head, *inputs, *workflows, *events, *changes, *agent_texts, *footer].join("\n")

      def self.default(option)
        shown = option.default.inspect
        (shown == "nil") ? "" : "`#{shown}`"
      end

      private

      def head
        ["# plastic #{@page.words}", "", "#{@page.summary}.", "", "```sh", @page.usage, "```", ""]
      end

      def inputs
        rows = @page.arguments.map { |arg| "| `#{arg.label}` | #{arg.text} | |" } + @page.options.map { |opt| "| `#{opt.switch}` | #{opt.text} | #{Page.default(opt)} |" }
        rows.empty? ? [] : ["| Argument or option | What it gives | Default |", "| --- | --- | --- |", *rows, ""]
      end

      def workflows
        return [] unless @page.flows.size > 1

        ["## The workflows of one call", "", "![The workflows of one call of plastic #{@page.words}](workflows.svg)", "",
          "Each box is a workflow. The words between the boxes say when the call moves on, and the last boxes say how the call ends.", ""]
      end

      def events
        ["## The events of one call, step by step", "", "![The events of one call of plastic #{@page.words}](events.svg)", "",
          "The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.", ""]
      end

      def changes
        found = @page.changes
        return ["## What one call changes", "", "This command changes nothing.", ""] if found.empty?

        ["## What one call changes", "", "| What changes | Where | Reach |", "| --- | --- | --- |", *found.map(&:table_row), "", *definition]
      end

      def definition
        travels = @page.changes.any? { |each| each.reach == Places::TRAVELS }
        travels ? [GOES_WITH_THE_STORE, ""] : []
      end

      def agent_texts
        rows = EventList.new(@page).events.select(&:said?).map(&:say_row)
        rows.empty? ? [] : ["## What the agent workflow steps print", "", "| Step | The text the agent gets |", "| --- | --- |", *rows, ""]
      end

      def footer
        ["The command is `#{@page.klass.name}`, in #{@links.file(@page.file)}.", ""]
      end
    end
  end
end
