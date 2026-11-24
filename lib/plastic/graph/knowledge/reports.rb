# frozen_string_literal: true

require_relative "../../layout"

module Plastic
  module Graph
    module Knowledge
      # The reports of a store that a sync reads: each one `plastic intent report` recorded for its intent, as a
      # `reported` line of the work log, and each one the setting reports.mandatory names, in every intent. A
      # mandatory name is a path inside resources/output/reports/; a recorded path is a path inside the intent
      # folder. The recorded reports load on the first question, from the store bound with `recorded_from`.
      class Reports
        FOLDER = Layout.resource(:reports)
        RECORDED = "SELECT intent_id, path FROM work_log WHERE kind = 'reported'"
        NOTHING = -> { [] }
        PARTS = ["", ".", ".."].freeze

        def self.none = new(mandatory: [])

        # The mandatory names of the setting, given as a list or as a comma value.
        def self.named(value) = (value.is_a?(Array) ? value : value.to_s.split(",")).map { |name| name.to_s.strip }.reject(&:empty?)

        def self.report?(rel) = rel.start_with?(FOLDER)

        # Why `rel` is no plain path inside resources/output/reports/, or nil. A plain path has no ., .. or empty part.
        def self.path_problem(rel)
          return "#{rel} is an absolute path; give the path inside the intent folder" if rel.start_with?("/")
          return "#{rel} holds a . or .. part or an empty part; give the plain path inside the intent folder" if rel.split("/", -1).intersect?(PARTS)

          "#{rel} is not in #{FOLDER}; a report lives there" unless report?(rel)
        end

        attr_reader :mandatory

        def initialize(mandatory:, recorded: NOTHING)
          @mandatory = mandatory
          @recorded = recorded
        end

        # The same mandatory names, with the recorded reports read from the store `database`.
        def recorded_from(database)
          Reports.new(mandatory:, recorded: -> { database.rows(RECORDED).map { |row| [row.fetch("intent_id"), row.fetch("path")] } })
        end

        def listed?(intent_id, rel) = mandatory?(rel) || recorded?(intent_id, rel)

        def mandatory?(rel) = @mandatory.include?(rel.delete_prefix(FOLDER)) && Reports.report?(rel)

        def recorded?(intent_id, rel) = !intent_id.nil? && recorded.include?([intent_id, rel])

        private

        def recorded = (@recorded_pairs ||= @recorded.call.to_set)
      end
    end
  end
end
