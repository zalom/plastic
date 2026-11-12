# frozen_string_literal: true

require_relative "../../../config"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The removal of a store's imported files, when the migrate flag asks
        # for it. It runs only after the store imported with no error; a
        # failure here keeps the rows already written and says what was left.
        class ImportCleanup
          def initialize(folder, retrieval, home)
            @folder = folder
            @retrieval = retrieval
            @home = home
          end

          def call(counts)
            remove(counts) if Config.new(@home).flag(%w[migrate remove_after_import], default: false)
          end

          private

          def remove(counts)
            archive_done_intents(counts)
            @folder.delete(StoreFolder::LEGACY_INDEX)
          rescue => error
            raise Invalid, "#{@retrieval.store}: imported, but removing the imported files stopped: #{error.message}"
          end

          def archive_done_intents(counts)
            work = Graph.open(home: @home, store: @retrieval.store).work
            archived = done_intent_ids.count { |id| work.archive_intent(id).first }
            counts[:archived] += archived if archived.positive?
          end

          def done_intent_ids = @retrieval.intents.select(&:closed?).map(&:intent_id)
        end
      end
    end
  end
end
