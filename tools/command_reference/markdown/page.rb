# frozen_string_literal: true

module CommandReference
  module Markdown
    # The README of one command.
    class Page
      DSL = "../../dsl/README.md"

      def initialize(page, base: "../../../../")
        @page = page
        @links = Links.new(base)
        @blocks = Source.new(nil)
      end

      def to_s = [*head, *inputs, *touches, *before_chain, *flow, *WorkflowSections.new(@page, @links, @blocks).lines, *outcomes].join("\n")

      private

      def head
        ["# plastic #{@page.words}", "", "#{@page.summary}.", "", *paragraphs(@page.comment),
          "```sh", @page.usage, "```", "",
          "The command is `#{Words.short(@page.klass)}`, in #{@links.code(@page.file, @page.line)}. " \
          "The words on this page, such as gate, step and outcome, are explained in [the command DSL](#{DSL}).", ""]
      end

      def paragraphs(comment) = @blocks.blocks(comment).flat_map { |kind, body| (kind == :code) ? ["```ruby", body, "```", ""] : [body, ""] }

      def inputs
        rows = @page.arguments.map { |arg| "| `#{arg.label}` | #{arg.text} | |" } + @page.options.map { |opt| "| `#{opt.switch}` | #{opt.text} | #{default(opt)} |" }
        rows.empty? ? [] : ["| Argument or option | What it gives | Default |", "| --- | --- | --- |", *rows, ""]
      end

      def default(option) = option.default.nil? ? "" : "`#{option.default.inspect}`"

      def touches = ["## What it touches", "", "![What plastic #{@page.words} touches](component.svg)", ""]

      def before_chain
        return [] unless @page.own_call

        ["## Before the chain", "", "The command's own `call`, at #{@links.code(@page.own_call.file, @page.own_call.line)}, runs first:", "",
          "```ruby", *@page.own_call.code, "```", ""]
      end

      def flow
        return ["## How the call flows", "", "![The call of plastic #{@page.words}](call.svg)", ""] if @page.flows.empty?

        ["## How the call flows", "", "![The chain of workflows that plastic #{@page.words} runs](chain.svg)", "",
          "| Workflow | Kind | Code |", "| --- | --- | --- |", *@page.flows.map { |each| flow_row(each) }, ""]
      end

      def flow_row(flow) = "| [#{Words.short(flow.klass)}](##{Words.short(flow.klass).downcase}) | #{flow.lane} | #{@links.code(flow.file, flow.line)} |"

      def outcomes
        ["## Outcomes", "", "Every call can also end in [the ways any call can end](#{DSL}#how-any-call-can-end).", "",
          "| Ending | Exit | next: | Code |", "| --- | --- | --- | --- |", *@page.endings.map { |ending| ending_row(ending) }, ""]
      end

      def ending_row(ending) = "| #{cell(ending.text)} | #{ending.exit_code} | #{cell(ending.next_text)} | #{@links.code(ending.file, ending.line)} |"

      def cell(text) = text.to_s.gsub("|", "\\|")
    end
  end
end
