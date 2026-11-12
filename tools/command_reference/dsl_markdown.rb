# frozen_string_literal: true

module CommandReference
  # The README of the DSL page: every section opens with its drawing, and a table under it links each word to its line.
  class DslMarkdown
    SECTIONS = [Dsl::CommandSection, Dsl::WorkflowsSection, Dsl::CodeSection, Dsl::AgentSection, Dsl::EndingsSection, Dsl::SharedSection, Dsl::FilesSection].freeze

    INTRO = [
      "# The command DSL", "",
      "Every plastic command is one Ruby class. The class declares what the command takes and its workflows, " \
      "and each workflow declares its steps and the ways it ends. Each drawing below shows real code from the kernel, " \
      "and each table links the line that defines a word.", ""
    ].freeze
    CONTENTS = [
      "| Section | The words it covers |", "| --- | --- |",
      "| [Declare a command](#declare-a-command) | `intent_subject`, `argument`, `option`, `reads`, `writes` |",
      "| [Wire the workflows](#wire-the-workflows) | `workflow`, `on`, `next:` |",
      "| [Declare a code workflow](#declare-a-code-workflow) | `sets`, `read`, `gate`, `step`, `outcome` |",
      "| [Declare an agent workflow](#declare-an-agent-workflow) | `step` with `say:`, `outcome` |",
      "| [How a call ends](#how-a-call-ends) | `Finished`, `HandedOff`, `Failed`, `Refused` |",
      "| [How any call can end](#how-any-call-can-end) | the endings every command shares |",
      "| [What every call shares](#what-every-call-shares) | `verify`, the usage error, the write lock |", ""
    ].freeze

    def initialize(dsl, base: "../../../")
      @dsl = dsl
      @links = Markdown::Links.new(base)
    end

    def to_s = [*head, *SECTIONS.flat_map { |section| section.new(@dsl, @links).lines }].join("\n")

    private

    def head = [*INTRO, *CONTENTS]
  end
end
