# frozen_string_literal: true

require_relative "../config"
require_relative "../errors"

module Plastic
  module Workflows
    # The one line a sync up says for each file type it skips and has not told
    # about yet, and the record that it told: the setting sync.asked.
    class TypeNotice
      LINE = "files of type .%<type>s are not synced; run plastic config set sync.types %<value>s to include them"
      NOT_RECORDED = [Config::HandEdited, Failed].freeze

      def initialize(config)
        @config = config
      end

      def lines(types)
        told = types.map { |type| format(LINE, type:, value: (@config.list("sync.types") | [type]).join(",")) }
        remember(types)
        told
      end

      private

      def remember(types)
        return if types.empty?

        @config.set("sync.asked", @config.list("sync.asked") | types)
      rescue *NOT_RECORDED
        nil
      end
    end
  end
end
