# frozen_string_literal: true

require "json"
require_relative "../intent"
require_relative "revision/section"

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
          def initialize(body, intent_id)
            @lines = body.split("\n", -1)
            @intent_id = intent_id
            @revised = []
          end

          # The text under `## Context`, as one line.
          def why = Section.lead(@lines.index("## Context") || @lines.size, @lines).reject(&:empty?).join(" ")

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
            close && @lines.index(text) <= close
          end

          def rewhy(why)
            return replace_lead("## Context", why) if @revised.include?("## Context")

            @revised.insert(@revised.index("## Outcome") || @revised.size, "## Context", "", why, "")
          end

          def replace_lead(heading, text)
            start = @revised.index(heading)
            return unless start

            old = Section.lead(start, @revised)
            @revised[start + 1, old.size] = Section.filled(old, text)
          end
        end
      end
    end
  end
end
