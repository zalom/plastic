# frozen_string_literal: true

module Plastic
  module Graph
    # Takes an intent off the checkout and puts it back. The rows never move;
    # only the folder and its `printed` rows come and go.
    class ArchiveWriter
      DONE_STATES = %w[done abandoned].freeze
      ARCHIVABLE_STATES = %w[done abandoned future].freeze

      def initialize(databases, retrieval, folder, session: nil)
        @databases = databases
        @retrieval = retrieval
        @folder = folder
        @session = session
      end

      # Returns [ok, problem, kind]; kind is :failure or :refusal, nil on success.
      def archive(intent_id)
        intent = @retrieval.intent(intent_id)
        return [false, "no intent #{intent_id}", :failure] unless intent

        problem = archive_problem(intent)
        return [false, problem, :refusal] if problem

        write_archive(intent)
        [true, nil, nil]
      end

      # Returns [ok, problem, kind]; kind is :failure, nil on success.
      def restore(intent_id)
        archive = @retrieval.archive_of(intent_id)
        return [false, "intent #{intent_id} is not archived", :failure] unless archive && archive.restored_at.nil?

        @databases.fetch(:work).transaction do |batch|
          batch.write(:archives, "UPDATE archives SET restored_at = :now WHERE origin_id = :origin AND intent_id = :intent_id",
            now: Plastic.now, origin: origin_id, intent_id:)
        end
        [true, nil, nil]
      end

      private

      def origin_id = @retrieval.origin_id

      def archive_problem(intent)
        return "intent #{intent.intent_id} is #{intent.status}; only done, abandoned and future intents archive" \
          unless ARCHIVABLE_STATES.include?(intent.status)

        live_link_problem(intent) || hand_edited_problem(intent)
      end

      def live_link_problem(intent)
        link = @retrieval.linking(intent.intent_id).find { |candidate| live?(candidate.from_ref) }
        "intent #{linking_intent_id(link.from_ref)} links to #{intent.intent_id}" if link
      end

      def live?(from_ref)
        from = @retrieval.intent(linking_intent_id(from_ref))
        from && !DONE_STATES.include?(from.status) && !@retrieval.archived?(from.intent_id)
      end

      def linking_intent_id(from_ref) = from_ref.split("/").first

      def hand_edited_problem(intent)
        printed = @retrieval.printed
        edited = @folder.files(intent.dir).find { |path| @folder.digest(path) != printed[path] }
        "intent #{intent.intent_id} has edits not synced; run plastic sync up first" if edited
      end

      def write_archive(intent)
        row = { intent_id: intent.intent_id, at: Plastic.now, restored_at: nil, session_id: @session }
        @databases.fetch(:work).transaction { |batch| batch.put(:archives, row, statement: :upsert) }
        @folder.remove_dir(intent.dir)
        remove_printed(intent.dir)
      end

      def remove_printed(dir)
        paths = @retrieval.printed.keys.select { |path| path.start_with?("#{dir}/") }
        return if paths.empty?

        Schema::STORE.each do |key|
          @databases.fetch(key).transaction { |batch| paths.each { |path| batch.remove(:printed, path:) } }
        end
      end
    end
  end
end
