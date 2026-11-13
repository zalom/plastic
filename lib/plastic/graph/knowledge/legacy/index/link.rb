# frozen_string_literal: true

require_relative "../closing"
require_relative "entry"
require_relative "parsed"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        module Index
          # One linked intent line and the headings above it.
          Link = Data.define(:section, :cluster, :found)

          # What one line says about its intent.
          class Link
            PATTERN = %r{\A- \[(?<id>\d+[a-z0-9]*) (?:—|-) (?<title>.+?)\]\((?<dir>store/[^/)]+)/[^)]*\)(?<rest>.*)\z}
            DATED = /\A(?<date>\d{4}-\d\d-\d\d)\b\s*(?<text>.*)\z/
            MARKER = /\A_\((?<word>[a-z]+)[^)]*\)_\z/
            CLOSED = %w[done abandoned].freeze

            def intent_id = found[:id]

            def status = SECTIONS[section]

            def clustered? = section == "Clusters"

            def placed? = status || QUIET.include?(section)

            def problem = "#{intent_id} sits under ## #{section}, which gives no status"

            def member = Member.new(cluster, intent_id)

            # The status the marker after a cluster line gives, such as _(done)_.
            def marked_status = SECTIONS[rest[MARKER, :word].to_s.capitalize]

            def entry = Entry.new(intent_id, found[:title], found[:dir], status, *closing)

            def marked_entry = Entry.new(intent_id, found[:title], found[:dir], marked_status, nil, nil, nil)

            private

            def rest = found[:rest].strip

            def detail = rest.sub(/\A(?:—|-)\s*/, "")

            # The date that opens a closed intent's detail, with the text after it.
            def dated = CLOSED.include?(status) ? detail.match(DATED) : nil

            # The disposition, the reason and the closing date of the line.
            def closing
              date, text = dated&.captures || [nil, detail]
              text = nil if text.empty?
              Closing.of(status, text, date)
            end
          end
        end
      end
    end
  end
end
