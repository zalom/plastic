# frozen_string_literal: true

require_relative "intent_file"
require_relative "../intent"
require_relative "../legacy/index"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # One intent folder of a store: its number, the row its own intent
        # file gives, and the reason it cannot give one.
        class IntentFolder
          attr_reader :dir

          def initialize(dir, folder)
            @dir = dir
            @folder = folder
          end

          def number = File.basename(dir).split("--", 2).first

          # Why no row can be read from this folder, as one line naming it, or nil.
          def problem
            return "#{dir}: no intent file #{file}" unless @folder.exist?(file)

            reason = intent_file.problem
            "#{dir}: its intent file does not parse: #{reason}" if reason
          end

          # Why this folder cannot be read for sharing its number with another of `folders`, or nil.
          def clash_among(folders)
            twins = folders.select { |other| number == other.number && !equal?(other) }
            "#{dir}: its number #{number} is also the number of #{twins.map(&:dir).join(", ")}" if twins.any?
          end

          def intent
            front = intent_file.front
            entry = Legacy::Index::Entry.new(front["id"], front["intent"], dir, "open", nil, nil)
            Intent.from_h(entry.row(front, Plastic.now))
          end

          private

          def file = "#{dir}/#{File.basename(dir)}.md"

          def intent_file = (@intent_file ||= IntentFile.new(@folder.read(file), number))
        end
      end
    end
  end
end
