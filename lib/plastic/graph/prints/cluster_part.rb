# frozen_string_literal: true

require "digest"
require "json"
require_relative "part"
require_relative "index_print"
require_relative "../knowledge/store_folder"

module Plastic
  module Graph
    module Prints
      # The clusters of store/index.json as a part of that file, with a path and a digest of their own: the
      # digest is the same for the same clusters in any order. Its print records a row and writes no file.
      module ClusterPart
        PATH = "#{Knowledge::StoreFolder::INDEX}#clusters".freeze

        module_function

        def path?(path) = path == PATH

        def call(retrieval) = Part.new(PATH, digest(IndexPrint.clusters(retrieval.clusters)), nil)

        def digest(clusters) = Digest::SHA256.hexdigest(JSON.generate(normal(clusters)))

        # The digest of the clusters an index file lists, nil when the file is no JSON object or lists none.
        def file_digest(text)
          data = JSON.parse(text.dup.force_encoding(Encoding::UTF_8))
          return unless data.is_a?(Hash) && data.key?("clusters")

          listed = data["clusters"]
          (listed.is_a?(Array) && listed.all?(Hash)) ? digest(listed) : Digest::SHA256.hexdigest(JSON.generate(listed))
        rescue JSON::ParserError
          nil
        end

        def normal(clusters)
          clusters.map { |cluster| { "name" => cluster["name"], "intents" => ids(cluster["intents"]) } }.sort_by { |cluster| cluster["name"].to_s }
        end

        def ids(listed) = listed.is_a?(Array) ? listed.map(&:to_s).sort : listed
      end
    end
  end
end
