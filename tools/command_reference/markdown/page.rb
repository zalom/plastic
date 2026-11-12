# frozen_string_literal: true

module CommandReference
  module Markdown
    # The README of one command.
    class Page
      DSL = "../../dsl/README.md"

      def initialize(page, base: "../../../../")
        @page = page
        @links = Links.new(base)
      end

      def to_s = [*head, *inputs, *components, *Events.new(@page, @links).lines, *Touching.new(@page, @links).lines, *endings, *LeavesOut.new(@page).lines].join("\n")

      def self.default(option)
        shown = option.default.inspect
        (shown == "nil") ? "" : "`#{shown}`"
      end

      private

      def head
        ["# plastic #{@page.words}", "", "#{@page.summary}.", "", *comment,
          "```sh", @page.usage, "```", "",
          "The command is `#{@page.klass.name.delete_prefix("Plastic::").delete_prefix("Commands::")}`, in #{@links.code(@page.file, @page.line)}. " \
          "The words on this page, such as gate, step and outcome, are explained in [the command DSL](#{DSL}).", ""]
      end

      def comment
        text = @page.comment
        Prose.repeats?(@page.summary, text) ? [] : Prose.lines(text)
      end

      def inputs
        rows = @page.arguments.map { |arg| "| `#{arg.label}` | #{arg.text} | |" } + @page.options.map { |opt| "| `#{opt.switch}` | #{opt.text} | #{Page.default(opt)} |" }
        rows.empty? ? [] : ["| Argument or option | What it gives | Default |", "| --- | --- | --- |", *rows, ""]
      end

      def components
        ["## Components", "", "![The components on the path of plastic #{@page.words}](component.svg)", "",
          "The figure shows the command, the workflows it runs, the classes behind them, and the databases and files they reach.", ""]
      end

      def endings
        ["## How a call ends", "", "Every call can also end in [the ways any call can end](#{DSL}#how-any-call-can-end).", "",
          "| Ending | Exit | next: | Code |", "| --- | --- | --- | --- |", *@page.endings.map { |ending| EndingRow.new(ending, @links).to_s }, ""]
      end
    end
  end
end
