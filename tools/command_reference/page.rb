# frozen_string_literal: true

module CommandReference
  ROW_KINDS = { read: "read", gate: "gate", step: "step", agent: "agent step" }.freeze

  # A gate or a step of a code workflow, with the line that declares it.
  Row = Data.define(:kind, :name, :check, :stops, :say, :file, :line) do
    def location = "#{File.basename(file)}:#{line}"

    def gate? = kind == :gate

    def headline = gate? ? "passes when #{check}" : name

    def reason = gate? ? name : "the step ran and its done check still fails"

    def kind_words = "#{ROW_KINDS.fetch(kind)}#{stops_words}"

    def stops_words = if gate?
                        ", stops with exit #{(stops == :refusal) ? 3 : 1}"
                      else
                        ""
                      end

    def saying = ["The agent step \"#{name}\" prints:", "", "> #{say.gsub("\n", "\n> ")}", ""]

    def check_cell = Array(check).map { |text| "`#{Words.cell(text)}`" }.join

    def gate_ending(step) = Ending.new(:gate, (step.stops == :refusal) ? 3 : 1, step.offers || Endings::NONE, name, file, line)
  end
  # One outcome line of a workflow.
  Outcome = Data.define(:name, :check, :fallback, :offers, :because, :to, :exit_code, :file, :line) do
    def ends? = to == :noop

    def exit_words = (name == :handoff) ? "hands off, exit #{exit_code}" : "finishes, exit 0"

    def next_words = Array(offers).map { |each| "next: #{each}" }.first || Endings::NONE

    def ending(kind) = Ending.new(kind, exit_code, offers || Endings::NONE, because, file, line)
  end
  # One workflow of a command's chain.
  Flow = Data.define(:key, :klass, :lane, :file, :line, :comment, :facts, :rows, :outcomes) do
    def agent? = lane == "agent"

    def short = Words.short(klass)

    def location = "#{File.basename(file)}:#{line}"

    def closing = outcomes.find(&:ends?)

    def captions = ["#{lane.upcase} WORKFLOW", short, ":#{key}"]

    def closing_words = agent? ? "hands off, exit #{closing.exit_code}" : "finishes, exit 0"

    def files = rows.filter_map(&:file) + [file]

    def raising? = lane == "code" && klass.steps.any? { |step| !step.is_a?(Plastic::CodeWorkflow::Gate) }

    def endings = gate_endings + outcomes.select(&:ends?).map { |outcome| outcome.ending(closing_kind(outcome)) }

    def closing_kind(outcome) = (agent? && outcome.name == :handoff) ? :handoff : :outcome

    def gate_endings = klass.steps.zip(rows).filter_map { |step, row| row.gate_ending(step) if step.is_a?(Plastic::CodeWorkflow::Gate) }
  end
  # One wire of a chain, with the outcomes it carries.
  Edge = Data.define(:from, :to, :outcomes) do
    def words = outcomes.compact.map { |name| ":#{name}" }.join(" ").then { |text| text.empty? ? "every outcome" : text }
  end
  # The call method a command writes for itself.
  OwnCall = Data.define(:file, :line, :code) do
    def responds = Ending.new(:respond, 0, Endings::NONE, "answers the event", file, line)
  end
  # One way a command call ends.
  Ending = Data.define(:kind, :exit_code, :next_text, :text, :file, :line)
  # What one command is made of: its files, its workflows and the call it writes itself.
  Reach = Data.define(:kind, :files, :flows, :own_call) do
    def hook? = kind == :hook

    def raising? = flows.any?(&:raising?)

    def all_endings(scans, rescued) = [*flows.flat_map(&:endings), *rescued, *file_endings(scans), *hook_endings(scans)]

    def file_endings(scans) = hook? ? [] : scans.flat_map(&:call)

    def hook_endings(scans) = hook? ? [own_call.responds, *scans.flat_map(&:decisions)] : []

    def scanned_files = [*files, *flows.flat_map(&:files)].uniq
  end

  # Everything one command page says, read from the kernel.
  Page = Data.define(:words, :klass, :kind, :file, :line, :summary, :comment, :usage, :arguments, :options, :own_call,
    :entry, :flows, :edges, :touches, :endings) do
    def slug = words.tr(" ", "-")

    def graph_lines = [*klass.writes.map { |graph| "writes #{graph}" }, *klass.reads.map { |graph| "reads #{graph}" }]

    def flow(key) = flows.find { |flow| flow.key == key }
  end
end
