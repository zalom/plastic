# frozen_string_literal: true

require "digest"
require "json"
require_relative "part"
require_relative "index_print"
require_relative "../knowledge/store_folder"

module Plastic
  module Graph
    module Prints
      # The links of store/index.json as a part of that file, with a path and a digest of their own: the digest holds
      # the key of each link, so the time a link was made is no change. Its print records a row and writes no file.
      module LinkPart
        PATH = "#{Knowledge::StoreFolder::INDEX}#links".freeze

        module_function

        def path?(path) = path == PATH

        def call(retrieval) = Part.new(PATH, :work, digest(IndexPrint.links(retrieval.every_link)), nil)

        def digest(links) = Digest::SHA256.hexdigest(JSON.generate(keys(links)))

        # The digest of the links an index file lists, nil when the file is no JSON object or has no links key.
        def file_digest(text)
          data = JSON.parse(text.dup.force_encoding(Encoding::UTF_8))
          return unless data.is_a?(Hash) && data.key?("links")

          listed = data["links"]
          listed.is_a?(Array) ? digest(listed) : Digest::SHA256.hexdigest(JSON.generate(listed))
        rescue JSON::ParserError
          nil
        end

        def keys(links)
          links.map { |link| link.is_a?(Hash) ? link.values_at("from_ref", "to_ref", "kind") : link }.sort_by { |key| JSON.generate(key) }
        end
      end
    end
  end
end
