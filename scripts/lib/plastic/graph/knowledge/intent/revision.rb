# frozen_string_literal: true

require "json"
require_relative "../intent"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # One intent file with a new What, and a new Why when one is given.
        # The What is the `intent:` front matter field, the `# ID - title`
        # heading and the text under `## Intent`. The Why is the text under
        # `## Context` up to the next heading. Each part the file holds is
        # replaced; a part it lacks is not added, except a Why with no
        # `## Context`, which gets one before `## Outcome`.
        class Revision
          HEADING = /\A##?#? /

          def initialize(body, intent_id)
            @lines = body.split("\n", -1)
            @intent_id = intent_id
          end

          # The text under `## Context`, as one line.
          def why
            start = @lines.index("## Context")
            start ? lead(start).reject(&:empty?).join(" ") : ""
          end

          def revise(line, why = nil)
            lines = @lines.map { |text| retitle(text, line) }
            lines = replace_lead(lines, "## Intent", line)
            lines = rewhy(lines, why) if why
            lines.join("\n")
          end

          private

          def retitle(text, line)
            return "intent: #{JSON.generate(line)}" if text.start_with?("intent: ") && front_matter?(text)
            return "# #{@intent_id} - #{line}" if text.start_with?("# #{@intent_id} - ")

            text
          end

          def front_matter?(text)
            close = @lines.first == "---" && @lines.drop(1).index("---")
            close ? @lines.index(text) <= close : false
          end

          def rewhy(lines, why)
            return replace_lead(lines, "## Context", why) if lines.include?("## Context")

            at = lines.index("## Outcome") || lines.size
            lines.dup.insert(at, "## Context", "", why, "")
          end

          def replace_lead(lines, heading, text)
            start = lines.index(heading)
            return lines unless start

            old = lead(start, lines)
            lines[0..start] + filled(old, text) + lines[(start + 1 + old.size)..]
          end

          def lead(start, lines = @lines) = lines[(start + 1)..].take_while { |text| !text.match?(HEADING) }

          # The section's blank lines kept around the new text; an empty section gets one blank line each side.
          def filled(old, text)
            return ["", text, ""] if old.all?(&:empty?)

            before = old.take_while(&:empty?)
            after = old.reverse.take_while(&:empty?)
            before + [text] + after
          end
        end
      end
    end
  end
end
