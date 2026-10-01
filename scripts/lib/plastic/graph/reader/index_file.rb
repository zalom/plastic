# frozen_string_literal: true

require "json"
require_relative "../../invalid"
require_relative "../intent"
require_relative "../store_folder"

module Plastic
  module Graph
    class Reader
      # A hand edit of store/index.json: the intent rows it lists, and the
      # clusters, which it replaces whole.
      class IndexFile
        def initialize(text, origin_id)
          @data = JSON.parse(text.force_encoding(Encoding::UTF_8))
          @origin_id = origin_id
        end

        def self.intent_row(entry) = Intent::INDEX_FIELDS.to_h { |field| [field, entry[field.to_s]] }.merge(updated_at: Plastic.now)

        def database = :work

        def apply(batch)
          batch.put_all(:intents, intents).remove(:clusters).put_all(:clusters, members)
        end

        private

        def intents = own(listed("intents")).map { |entry| IndexFile.intent_row(entry) }

        def own(entries)
          foreign = entries.find { |entry| entry["origin_id"] != @origin_id }
          return entries unless foreign

          raise Invalid, "#{StoreFolder::INDEX} lists #{foreign["intent_id"]} of origin #{foreign["origin_id"]}; " \
                         "a store holds only its own intents"
        end

        def members = listed("clusters").flat_map { |cluster| Cluster.new(cluster).rows }

        def listed(field) = Array(@data[field])

        # One cluster of the file: a name and the intents it holds.
        class Cluster
          def initialize(entry)
            @name = entry["name"]
            @intent_ids = entry["intents"]
          end

          def rows = @intent_ids.map { |intent_id| { name: @name, intent_id: } }
        end
      end
    end
  end
end
