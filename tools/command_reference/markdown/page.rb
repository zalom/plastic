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

      def to_s = [*head, *inputs, *touches, *before_chain, *flow, *WorkflowSections.new(@page, @links).lines, *outcomes].join("\n")

      def self.default(option)
        shown = option.default.inspect
        (shown == "nil") ? "" : "`#{shown}`"
      end

      private

      def head
        ["# plastic #{@page.words}", "", "#{@page.summary}.", "", *Prose.lines(@page.comment),
          "```sh", @page.usage, "```", "",
          "The command is `#{Words.short(@page.klass)}`, in #{@links.code(@page.file, @page.line)}. " \
          "The words on this page, such as gate, step and outcome, are explained in [the command DSL](#{DSL}).", ""]
      end

      def inputs
        rows = @page.arguments.map { |arg| "| `#{arg.label}` | #{arg.text} | |" } + @page.options.map { |opt| "| `#{opt.switch}` | #{opt.text} | #{Page.default(opt)} |" }
        rows.empty? ? [] : ["| Argument or option | What it gives | Default |", "| --- | --- | --- |", *rows, ""]
      end

      def touches = ["## What it touches", "", "![What plastic #{@page.words} touches](component.svg)", ""]

      def before_chain
        own = @page.own_call
        return [] unless own

        ["## Before the chain", "", "The command's own `call`, at #{@links.at(own)}, runs first:", "", "```ruby", *own.code, "```", ""]
      end

      def flow
        flows = @page.flows
        words = @page.words
        return ["## How the call flows", "", "![The call of plastic #{words}](call.svg)", ""] if flows.empty?

        ["## How the call flows", "", "![The chain of workflows that plastic #{words} runs](chain.svg)", "",
          "| Workflow | Kind | Code |", "| --- | --- | --- |", *flows.map { |each| FlowRow.new(each, @links).to_s }, ""]
      end

      def outcomes
        ["## Outcomes", "", "Every call can also end in [the ways any call can end](#{DSL}#how-any-call-can-end).", "",
          "| Ending | Exit | next: | Code |", "| --- | --- | --- | --- |", *@page.endings.map { |ending| EndingRow.new(ending, @links).to_s }, ""]
      end
    end
  end
end
