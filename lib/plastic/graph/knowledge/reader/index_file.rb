# frozen_string_literal: true

require "json"
require_relative "../../../invalid"
require_relative "../intent"
require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # A hand edit of store/index.json: the intent rows it lists. Its clusters are read by ClusterFile.
        # An index that another home printed gives no row of its own: it replaces the title and the state of the rows of this home.
        class IndexFile
          # `dirs` are the intent folders on disk. An entry with no folder is broken data and gets no row; nil keeps every entry.
          # `rows` are the intents of this home by intent id, for an index that another home printed.
          def initialize(text, origin_id, dirs = nil, rows = {}, clock:)
            @data = JSON.parse(text.force_encoding(Encoding::UTF_8))
            @origin_id = origin_id
            @dirs = dirs
            @rows = rows
            @clock = clock
          end

          def self.intent_row(entry, updated_at) = Intent::INDEX_FIELDS.to_h { |field| [field, entry[field.to_s]] }.merge(status: Intent.stored_state(entry["status"]), updated_at:)

          # The cluster rows alone, for a home that holds none.
          def cluster_rows = members

          def apply(batch)
            batch.put_all(:intents, intents)
          end

          private

          def intents = foreign? ? crossing : own(housed(listed("intents"))).map { |entry| IndexFile.intent_row(entry, Plastic.timestamp(@clock.now)) }

          def foreign? = !object["origin_id"].nil? && object["origin_id"] != @origin_id

          def crossing = own(housed(listed("intents")), object["origin_id"]).filter_map { |entry| crossed(entry) }

          # The row of this home with the fields that cross taken from the entry; nil when this home holds no row or the fields are level.
          def crossed(entry)
            row = @rows[entry["intent_id"]]
            return unless row&.origin_id == @origin_id

            fields = Intent::CROSSING_FIELDS.to_h { |field| [field, entry[field.to_s]] }.merge(status: Intent.stored_state(entry["status"]))
            row.new_row.merge(fields, updated_at: stamp) unless fields.all? { |field, value| row.public_send(field) == value }
          end

          def stamp = Plastic.timestamp(@clock.now)

          def housed(entries) = @dirs ? entries.select { |entry| housed?(entry["intent_id"]) } : entries

          def housed?(intent_id) = @dirs.any? { |dir| dir.start_with?("store/#{intent_id}--") }

          def own(entries, origin_id = @origin_id)
            foreign = entries.find { |entry| entry["origin_id"] != origin_id }
            return entries unless foreign

            raise Invalid, "#{StoreFolder::INDEX} lists #{foreign["intent_id"]} of origin #{foreign["origin_id"]}; " \
                           "a store holds only its own intents"
          end

          def members = listed("clusters").flat_map { |cluster| Cluster.new(cluster).rows }

          def listed(field)
            entries = Array(object[field])
            return entries if entries.all?(Hash)

            raise Invalid, "#{StoreFolder::INDEX} lists an entry under #{field} that is not a JSON object"
          end

          def object
            return @data if @data.is_a?(Hash)

            raise Invalid, "#{StoreFolder::INDEX} is not a JSON object"
          end

          # One cluster of the file: a name and the intents it holds.
          class Cluster
            def initialize(entry)
              @name = entry["name"]
              @intent_ids = entry["intents"]
            end

            def rows = intent_ids.map { |intent_id| { name: @name, intent_id: } }

            private

            def intent_ids
              return @intent_ids if @intent_ids.is_a?(Array)

              raise Invalid, "#{StoreFolder::INDEX} lists the cluster #{@name} with no list of intents"
            end
          end
        end
      end
    end
  end
end
