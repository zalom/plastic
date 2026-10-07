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
            @revised = []
          end

          # The section's blank lines kept around the new text; an empty section gets one blank line each side.
          def self.filled(old, text)
            return ["", text, ""] if old.all?(&:empty?)

            before = old.take_while(&:empty?)
            after = old.reverse.take_while(&:empty?)
            before + [text] + after
          end

          # The lines of a section, from its heading up to the next heading.
          def self.lead(start, lines) = lines[(start + 1)..].take_while { |text| !text.match?(HEADING) }

          # The text under `## Context`, as one line.
          def why
            start = @lines.index("## Context")
            start ? Revision.lead(start, @lines).reject(&:empty?).join(" ") : ""
          end

          def revise(line, why = nil)
            @revised = @lines.map { |text| retitle(text, line) }
            replace_lead("## Intent", line)
            rewhy(why) if why
            @revised.join("\n")
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

          def rewhy(why)
            return replace_lead("## Context", why) if @revised.include?("## Context")

            @revised.insert(@revised.index("## Outcome") || @revised.size, "## Context", "", why, "")
          end

          def replace_lead(heading, text)
            start = @revised.index(heading)
            return unless start

            old = Revision.lead(start, @revised)
            @revised[start + 1, old.size] = Revision.filled(old, text)
          end
        end
      end
    end
  end
end
