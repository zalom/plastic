# frozen_string_literal: true

require_relative "../../scripts/lib/plastic/code_workflow"
require_relative "../../scripts/lib/plastic/agent_workflow"
require_relative "../../scripts/lib/plastic/routine"
require_relative "../../scripts/lib/plastic/hook"

# Routines, workflows and hooks that exist only for the kernel tests. They
# live in their own namespace, with their own registry and command table, so
# no test adds a key to Plastic::Workflows::REGISTRY or Plastic::CLI::TABLE.
module Fixtures
  module Workflows
    REGISTRY = %i[code_stamp code_greet code_find_draft agent_write_draft code_hold code_hole
      code_break code_stuck agent_review code_who code_choose agent_greet].freeze

    class Stamp < Plastic::CodeWorkflow
      sets :stamp

      step "stamp the call", done: ->(c) { !c.stamp.nil? } do |c|
        c[:stamp] = SecureRandom.hex(4)
      end
    end

    class Greet < Plastic::CodeWorkflow
      sets :greeting

      read "greet" do |c|
        c[:greeting] = "hello #{c.name}"
        c.print(c.greeting)
      end

      outcome :done, offers: "plastic kernel two %{name}", because: "greeted %{name}"
    end

    class FindDraft < Plastic::CodeWorkflow
      sets :draft_path

      read "find the draft" do |c|
        c[:draft_path] = File.join(c.dir, "#{c.name}.md")
      end
    end

    class WriteDraft < Plastic::AgentWorkflow
      step "write", done: ->(c) { File.exist?(c.draft_path) }, say: "Write the draft to %{draft_path}"

      outcome :handoff, offers: "plastic kernel draft %{name}", because: "the draft for %{name} is not written yet"
      outcome :done, because: "the draft for %{name} is written, stamped %{stamp}"
    end

    class Hold < Plastic::CodeWorkflow
      gate "the owner holds %{mode}", stops: :refusal, pass: ->(c) { c.mode != "hold" }
      gate "the check broke on %{mode}", stops: :failure, pass: ->(c) { c.mode != "break" }

      outcome :done, because: "passed %{mode}"
    end

    class Hole < Plastic::CodeWorkflow
      sets :missing

      outcome :done, because: "found %{missing}"
    end

    class Break < Plastic::CodeWorkflow
      step "explode", done: ->(_c) { false } do |_c|
        raise "boom"
      end

      outcome :done, because: "exploded"
    end

    class Stuck < Plastic::CodeWorkflow
      step "never lands", done: ->(_c) { false } do |_c|
        nil
      end

      outcome :done, because: "landed"
    end

    class Review < Plastic::AgentWorkflow
      step "review", done: ->(_c) { false }, say: "Review the change"

      outcome :handoff, because: "the review is open", stops: :failure
      outcome :done, because: "reviewed"
    end

    class Who < Plastic::CodeWorkflow
      read "who" do |c|
        c.print("session #{c.session.inspect}")
      end

      outcome :done, because: "named the session"
    end

    class Choose < Plastic::CodeWorkflow
      outcome :yes, if: ->(_c) { true }, because: "chose yes"
    end
  end

  class Routine < Plastic::Routine
    def self.workflows = Workflows
  end

  class TwoStep < Routine
    argument :name, label: "NAME", text: "who to greet"

    workflow :code_stamp, next: :code_greet
    workflow :code_greet, next: :noop
  end

  class Draft < Routine
    subject :name
    argument :name, label: "NAME", text: "the draft's name"
    option :dir, switch: "--dir DIR", text: "where the draft goes"
    writes :work

    workflow :code_stamp, next: :code_find_draft
    workflow :code_find_draft, next: :agent_write_draft
    workflow :agent_write_draft, next: :noop
  end

  class Gate < Routine
    argument :mode, label: "MODE", text: "pass, hold or break"
    writes :work

    workflow :code_hold, next: :noop
  end

  class Holed < Routine
    workflow :code_hole, next: :noop
  end

  class Broken < Routine
    workflow :code_break, next: :noop
  end

  class Stalled < Routine
    workflow :code_stuck, next: :noop
  end

  class Reviewed < Routine
    workflow :agent_review, next: :noop
  end

  class Named < Routine
    workflow :code_who, next: :noop
  end

  class Backward < Routine
    workflow :code_stamp, next: :code_greet
    workflow :code_greet, next: :code_stamp
  end

  class Echo < Plastic::Hook
    def respond(event) = "session #{event[:session_id]}"
  end

  class Quiet < Plastic::Hook
    def respond(_event) = nil
  end

  TABLE = {
    "kernel two" => ["Fixtures::TwoStep", "Greet in two steps"],
    "kernel draft" => ["Fixtures::Draft", "Hand a draft to the agent"],
    "kernel gate" => ["Fixtures::Gate", "Stop at a gate"],
    "kernel hole" => ["Fixtures::Holed", "Close on a fact with no value"],
    "kernel break" => ["Fixtures::Broken", "Raise inside a step"],
    "kernel stuck" => ["Fixtures::Stalled", "Run a step that never lands"],
    "kernel review" => ["Fixtures::Reviewed", "Hand off as a failure"],
    "kernel backward" => ["Fixtures::Backward", "Point an edge backward"],
    "kernel who" => ["Fixtures::Named", "Print the session"],
    "hook echo" => ["Fixtures::Echo", "Echo the session"],
    "hook quiet" => ["Fixtures::Quiet", "Say nothing"]
  }.freeze
end
