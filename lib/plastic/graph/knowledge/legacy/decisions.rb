# frozen_string_literal: true

require_relative "decision_bullets"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Reads the rulings and references of every intent folder from the original legacy document bytes.
        module Decisions
          RULING_ID = /\A\*{0,2}D(\d+)\b/

          def self.read(dirs, originals) = dirs.map { |dir| read_one(dir, originals) }

          def self.read_one(dir, originals)
            name = File.basename(dir)
            main, spec = ["#{name}.md", Layout.name(:spec)].map { |file| text_of(originals["#{dir}/#{file}"]) }
            bullets = [spec, main].map { |text| DecisionBullets.call(text) }.find(&:any?) || []
            { intent_id: name.split("--").first, rulings: assign_ruling_ids(bullets),
              source: front_matter_refs(main, "sources"), chain: front_matter_refs(main, "chain") }
          end

          def self.text_of(bytes) = bytes.to_s.dup.force_encoding(Encoding::UTF_8)

          def self.assign_ruling_ids(bullets)
            taken = []
            bullets.map do |bullet|
              number = bullet[RULING_ID, 1].to_i
              number = (taken.max || 0) + 1 if number.zero? || taken.include?(number)
              taken << number
              ["D#{number}", bullet]
            end
          end

          def self.front_matter_refs(text, key)
            line = text[/^#{Regexp.escape(key)}:\s*(\[.*\])\s*$/, 1]
            line ? line.scan(/"([^"]+)"/).flatten : []
          end
        end
      end
    end
  end
end
