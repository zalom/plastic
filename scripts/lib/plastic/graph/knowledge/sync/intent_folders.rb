# frozen_string_literal: true

require_relative "legacy_import"
require_relative "../intent"
require_relative "../legacy/index"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The intent folders of a store, whatever store/index.json says. A
        # folder whose intent has no row gives a row built from the fields of
        # its own file, the way the legacy import builds one. A folder that
        # cannot give a row is a problem named with its reason, and none of its
        # files are read.
        class IntentFolders
          REQUIRED = %w[id intent created].freeze

          def initialize(folder, retrieval)
            @folder = folder
            @rowed = retrieval.intents.to_h { |intent| [intent.intent_id, intent.dir] }
          end

          # The intents of the folders that have no row and can be read.
          def intents = readable.map { |dir, front| intent(dir, front) }

          # One line for each folder that cannot be read: its path and the reason.
          def problems = unreadable_entries.values.flatten

          # The paths of the folders that cannot be read.
          def unreadable = unreadable_entries.keys

          private

          def unreadable_entries = checked.select { |_dir, found| found.is_a?(Array) }

          def readable = checked.reject { |_dir, found| found.is_a?(Array) }

          def checked = (@checked ||= clashes.merge((unrowed - clashes.keys).to_h { |dir| [dir, inspect_folder(dir)] }))

          def unrowed = @folder.intent_dirs.reject { |dir| @rowed[number(dir)] == dir }

          def number(dir) = File.basename(dir).split("--", 2).first

          # Folders that share a number with another folder: each is named with its twins.
          def clashes
            @folder.intent_dirs.group_by { |dir| number(dir) }.select { |_number, dirs| dirs.size > 1 }
              .flat_map { |number, dirs| clash(number, dirs) }.to_h
          end

          def clash(number, dirs)
            dirs.reject { |dir| @rowed[number] == dir }.map do |dir|
              others = (dirs - [dir]).join(", ")
              [dir, ["#{dir}: its number #{number} is also the number of #{others}"]]
            end
          end

          def inspect_folder(dir)
            file = "#{dir}/#{File.basename(dir)}.md"
            return ["#{dir}: no intent file #{file}"] unless @folder.exist?(file)

            front = front_matter(file)
            reason = unparsed(front, number(dir))
            reason ? ["#{dir}: its intent file does not parse: #{reason}"] : front
          end

          def front_matter(file)
            text = @folder.read(file).force_encoding(Encoding::UTF_8)
            text.valid_encoding? ? text[LegacyImport::FRONT_MATTER, 1].to_s.scan(LegacyImport::FIELD).to_h : {}
          end

          def unparsed(front, number)
            missing = REQUIRED.select { |field| front[field].to_s.strip.empty? }
            return "it has no #{missing.join(", ")} in its front matter" if missing.any?

            "its id #{front["id"]} is not the folder number #{number}" unless front["id"] == number
          end

          def intent(dir, front)
            entry = Legacy::Index::Entry.new(front["id"], front["intent"], dir, "open", nil, nil)
            Intent.from_h(entry.row(front, Plastic.now))
          end
        end
      end
    end
  end
end
