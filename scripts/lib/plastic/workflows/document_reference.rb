# frozen_string_literal: true

require "uri"
require_relative "../cli/command/usage"

module Plastic
  module Workflows
    # A qualified document reference, plastic://STORE/INTENT/PATH with an optional revision.
    class DocumentReference
      SHAPE = /\Aplastic:\/\/[^\/]+\/[^\/]+\/[^?]*(?:\?revision=[0-9a-f]{64})?\z/

      def initialize(text)
        @text = text
      end

      def source_slug
        raise CLI::Command::Usage, "invalid document reference #{@text.inspect}" unless valid?

        @text[/\Aplastic:\/\/([^\/]+)/, 1]
      end

      private

      def valid? = SHAPE.match?(@text) && valid_path?

      def valid_path?
        URI::DEFAULT_PARSER.unescape(@text.split("/", 5).last.split("?", 2).first).force_encoding(Encoding::UTF_8).valid_encoding?
      end
    end
  end
end
