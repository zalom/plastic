# frozen_string_literal: true

require_relative "intent"
require_relative "store_folder"
require_relative "prints/print"
require_relative "prints/contents"
require_relative "prints/index_print"
require_relative "prints/parts"
require_relative "prints/graph_print"
require_relative "prints/context_print"

module Plastic
  module Graph
    # The files printed from a store's rows, each with the database that
    # owns its rows. Paths are relative to the store folder:
    #
    # - store/index.json lists this installation's intents, the archives now in force, the clusters and the links.
    # - store/ID--SLUG/PATH is a document, byte for byte.
    # - store/ID--SLUG/work.log holds the work log lines.
    # - store/ID--SLUG/graph.json holds the go-ahead, the completion, the verdicts, the nodes with their criterion keys and runs, and the edges.
    # - store/ID--SLUG/context.json holds the saved discovery and context of the intent.
    # - any other file of the folder is a kept file, from the SQL archive.
    #
    # The same rows always print the same bytes, so a hash tells whether a
    # file or its rows changed since the last print.
    module Prints
      WORK_LOG = "work.log"

      module_function

      def index(retrieval) = IndexPrint.call(retrieval)

      def parts(retrieval) = Parts.call(retrieval)

      def hand_edit_line(path) = "#{path} changed since its last print on this home, by hand or in a copy from another home; run plastic sync up first to read it into rows"

      def unreadable_line(path, reason) = "#{path} changed by hand and cannot be read into rows: #{reason}"

      def empty_graph_sha(path) = GraphPrint.empty_sha(path)

      # Every file of the store, read in eight queries whatever the number of intents.
      def of_store(retrieval)
        rows = Contents.read(retrieval)
        [index(retrieval), *retrieval.unarchived_intents.flat_map { |intent| of_intent_contents(retrieval, intent, rows) }]
      end

      # The print of the work log of one intent.
      def log_of(retrieval, intent_id) = of_intent(retrieval, retrieval.intent(intent_id)).select { |print| print.path.end_with?("/" + WORK_LOG) }

      def of_intent(retrieval, intent) = of_intent_contents(retrieval, intent, Contents.read(retrieval, intent.intent_id))

      def of_intent_contents(retrieval, intent, contents)
        id = intent.intent_id
        legacy = contents.legacy_intents_data(id)
        dir = intent.dir
        [*documents(dir, contents.documents(id), legacy), *text_files(dir, legacy), *work_log(intent, contents.work_log(id)),
          GraphPrint.call(intent, contents), *ContextPrint.call(intent, contents), *kept_files(retrieval, contents.kept_files(id))]
      end

      # A path held as a legacy row and as a document prints from the legacy row only; work.log prints from the work log lines alone.
      def documents(dir, rows, legacy)
        held = [*legacy.map(&:path), WORK_LOG]
        text_files(dir, rows.reject { |document| held.include?(document.path) })
      end

      def text_files(dir, rows) = rows.map { |row| Print.text("#{dir}/#{row.path}", row.body) }

      # A kept file is compared by its hash; its bytes are read only to write it.
      def kept_files(retrieval, rows)
        rows.map do |kept|
          name = kept.name
          Print.new(name, kept.sha256, -> { retrieval.stored.kept_file_data(name) })
        end
      end

      def work_log(intent, lines)
        return [] if lines.empty?

        [Print.text("#{intent.dir}/#{WORK_LOG}", lines.map { |line| "#{line.line}\n" }.join)]
      end
    end
  end
end
