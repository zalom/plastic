# frozen_string_literal: true

# Draws the call flow figures for docs/contributing: one command call of the
# live command line, one routine call of the kernel, one hook call, and one
# run of bin/verify-change. Each figure is a column of steps, indented by
# depth, with a note beside each step. Run it from the repository root:
#
#   ruby docs/resources/call_flows.rb
module CallFlows
  COLORS = { ink: "#1f2328", line: "#57606a", note: "#57606a", ok: "#1a7f37", agent: "#0969da", failed: "#cf222e", owner: "#9a6700" }.freeze

  # One step: its depth in the call, its title, its note, and its outline color.
  Step = Data.define(:depth, :title, :note, :color) do
    def self.[](depth, title, note = "", color = :line) = new(depth, title, note, color)
  end

  WIDTH = 960
  ROW = 56
  BOX = 40
  INDENT = 36

  FIGURES = {
    "command-call" => ["One call of a live command, from bin/plastic to the exit code", [
      Step[0, "bin/plastic", "runs Plastic::CLI.call with the arguments"],
      Step[1, "Find the command", "one frozen table: name, file, class and help line"],
      Step[1, "Print the usage line on --help", "nothing is built"],
      Step[1, "Build the command", "Command.call with the rest of the arguments"],
      Step[2, "call", "the work of one command"],
      Step[2, "flush", "prints the result, or its JSON form"],
      Step[0, "Exit 0, 1, 2 or 3", "succeeded, failed, called wrongly, refused", :ok]
    ]],
    "routine-call" => ["One call of a routine command through the kernel", [
      Step[0, "Plastic::CLI.call", "the kernel's dispatcher"],
      Step[1, "Find the command", "the longest table entry that starts the arguments"],
      Step[1, "Load its class", "only on the first call"],
      Step[1, "Build the command", "Command.call, then check that a named project exists"],
      Step[2, "Verify the chain", "once per process; raises every wiring fault at once"],
      Step[2, "Open the routine run", "the open row for this tool and subject, or a new one"],
      Step[2, "Build the context", "saved facts first, then this call's arguments"],
      Step[3, "Run the workflow", "it returns an outcome name or an end value"],
      Step[3, "Follow the edge", "the edge that carries that outcome"],
      Step[3, "Save the routine run", "after each workflow, for a tool that writes"],
      Step[3, "Repeat", "until an end value, or until the edge reaches :noop"],
      Step[2, "Close the routine run", "the end value names its status and its lines"],
      Step[2, "Report", "the printed lines, next: and because:, then the wrote: line"],
      Step[1, "flush", "prints the rows, or one JSON document with --json"],
      Step[0, "Exit 0, 1 or 3", "a usage error still exits 2", :ok]
    ]],
    "hook-call" => ["One call of a hook command", [
      Step[0, "The harness sends an event", "JSON on stdin"],
      Step[1, "Read the event", "empty input is an empty event"],
      Step[1, "Respond to the event", "the subclass returns text, or nil"],
      Step[1, "Print the text", "on stdout, only when there is text"],
      Step[0, "Exit 0", "on any error: one line on stderr, then exit 0 all the same", :ok]
    ]],
    "verify-change" => ["One run of bin/verify-change against origin/alpha", [
      Step[0, "Find the merge base", "with origin/alpha"],
      Step[0, "List the changed files", "Ruby sources under scripts/, lib/, tools/ or bin/lib/, and their tests"],
      Step[0, "Stop when a changed source has no test file", "exit 1", :failed],
      Step[0, "Make a throwaway HOME and PLASTIC_TMP", "for every step below"],
      Step[1, "Lint", "RuboCop on every changed Ruby file"],
      Step[1, "Tests", "the tests for the changed files, with coverage on"],
      Step[2, "Red tests stop the gate here", "a failing test kills every mutant", :failed],
      Step[1, "Patch coverage", "every changed line and branch"],
      Step[1, "Mutation testing", "Mutineer on the changed lines"],
      Step[1, "CRAP scores", "each changed method"],
      Step[1, "Code smells", "Reek on the changed sources, with .reek.yml"],
      Step[1, "RubyCritic score", "the changed sources that no todo list names"],
      Step[0, "Print the result", "\"Change verified\", or the names of the steps that failed"],
      Step[0, "Exit 0, 1 or 2", "verified, a check failed, a usage or git error", :ok]
    ]]
  }.freeze

  def self.call(dir = __dir__)
    FIGURES.each { |name, (label, steps)| File.write(File.join(dir, "#{name}.svg"), svg(label, steps)) }
  end

  def self.svg(label, steps)
    [header(label, 20 + (steps.size * ROW)), *boxes(steps), *arrows(steps), "</svg>"].join("\n")
  end

  def self.boxes(steps) = steps.each_with_index.map { |step, index| box(step, top(index)) }

  def self.arrows(steps) = steps.each_cons(2).with_index.map { |(from, to), index| arrow(from, to, top(index)) }

  def self.top(index) = 20 + (index * ROW)

  def self.box(step, top)
    left = 20 + (step.depth * INDENT)
    width = WIDTH - 40 - (step.depth * INDENT)
    [rect(left, top, width, COLORS.fetch(step.color)), words(step, left, top, width)].join("\n")
  end

  def self.rect(left, top, width, color)
    %(<rect x="#{left}" y="#{top}" width="#{width}" height="#{BOX}" rx="6" fill="#ffffff" stroke="#{color}" stroke-width="2"/>)
  end

  def self.words(step, left, top, width)
    <<~SVG.chomp
      <text x="#{left + 14}" y="#{top + 25}" class="title">#{step.title}</text>
      <text x="#{left + width - 14}" y="#{top + 25}" class="note">#{step.note}</text>
    SVG
  end

  def self.arrow(from, to, top)
    x = 20 + ([from.depth, to.depth].min * INDENT) + 24
    %(<polyline points="#{x},#{top + BOX} #{x},#{top + ROW - 2}" fill="none" stroke="#{COLORS[:line]}" stroke-width="1.5" marker-end="url(#head)"/>)
  end

  def self.header(label, height)
    <<~SVG.chomp
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{WIDTH} #{height}" role="img" aria-label="#{label}">
      <style>text { font: 14px sans-serif; fill: #{COLORS[:ink]}; } .title { font-weight: 700; } .note { fill: #{COLORS[:note]}; text-anchor: end; }</style>
      <defs><marker id="head" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="#{COLORS[:line]}"/></marker></defs>
      <rect width="#{WIDTH}" height="#{height}" fill="#ffffff"/>
    SVG
  end
end

CallFlows.call if $PROGRAM_NAME == __FILE__
