# frozen_string_literal: true

require "digest"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Which changed files are a hand edit of the spec or the outcome of a closed intent. A closed intent keeps both as
        # it closed, so sync up reads no hand edit of them, and sync down prints them again from the rows. The one change
        # it reads is an amendment: the resource sort rewrites a link and leaves an `amended` line with the new text's sha.
        class ClosedEdits
          FILES = [Layout.name(:spec), Layout.name(:outcome)].freeze
          CLOSED = %w[done abandoned].freeze
          AMENDED = "SELECT intent_id, path, sha256 FROM work_log WHERE kind = 'amended'"

          def initialize(folder, retrieval, database)
            @folder = folder
            @closed = retrieval.intents.select { |intent| CLOSED.include?(intent.status) }.flat_map { |intent| self.class.files(intent) }.to_h
            @amended = database.rows(AMENDED).map(&:values)
          end

          # The spec and the outcome paths of `intent`, each with the intent.
          def self.files(intent) = FILES.map { |name| ["#{intent.dir}/#{name}", intent] }

          # The reason for each of `paths` that is a hand edit of a closed intent's spec or outcome, by path.
          def call(paths) = paths.filter_map { |path| refused(path) }.to_h

          private

          def refused(path)
            intent = @closed[path]
            return unless intent && !amended?(intent, path)

            [path, "intent #{intent.intent_id} is #{intent.status}, and a closed intent keeps its #{File.basename(path)} as it closed"]
          end

          # A removed file is no amendment.
          def amended?(intent, path)
            File.file?(@folder.path(path)) && @amended.include?([intent.intent_id, File.basename(path), Digest::SHA256.hexdigest(@folder.read(path))])
          end
        end
      end
    end
  end
end
