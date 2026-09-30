# frozen_string_literal: true

require_relative "../invalid"

module Plastic
  module Graph
    # Reads the INDEX.md of a store written before store/index.json. Each
    # status section gives its intents a status; a line may add a closing
    # date and a disposition. A Clusters section names clusters, and an
    # intent listed only there takes the status its marker gives. The
    # import reads it once and deletes it.
    module LegacyIndex
      SECTIONS = { "Open" => "open", "Active" => "active", "Parked" => "parked", "Future" => "future",
                   "Completed" => "done", "Done" => "done", "Abandoned" => "abandoned" }.freeze
      QUIET = %w[Clusters Relocated].freeze
      MARKERS = SECTIONS.transform_keys(&:downcase).freeze
      LINK = %r{\A- \[(?<id>\d+[a-z0-9]*) (?:—|-) (?<title>.+?)\]\((?<dir>store/[^/)]+)/[^)]*\)(?<rest>.*)\z}
      DATED = /\A(?<date>\d{4}-\d\d-\d\d)\b\s*(?<text>.*)\z/
      MARKER = /\A_\((?<word>[a-z]+)[^)]*\)_\z/

      # One intent of the file: its status and what its line adds.
      Entry = Data.define(:intent_id, :title, :dir, :status, :disposition, :closed_at)

      # One intent's membership of a named cluster.
      Member = Data.define(:name, :intent_id)

      module_function

      def parse(text) = Reading.new(text).parsed

      # The entries and clusters of one file.
      Parsed = Data.define(:entries, :clusters) do
        # Every intent folder must have an entry and every entry a folder;
        # a guess would import a record nobody wrote.
        def check(dirs)
          listed = entries.map(&:dir)
          problems = (dirs - listed).map { |dir| "#{dir} has no entry in INDEX.md" } +
            (listed - dirs).map { |dir| "#{dir} is in INDEX.md and has no folder" }
          raise Invalid, problems.join("; ") if problems.any?

          self
        end
      end

      # One pass over the lines, section by section.
      class Reading
        def initialize(text)
          @entries = {}
          @marked = {}
          @clusters = []
          @problems = []
          text.each_line(chomp: true) { |line| take(line) }
        end

        def parsed
          @marked.each { |id, entry| @entries[id] ||= entry }
          raise Invalid, "INDEX.md: #{@problems.join("; ")}" if @problems.any?

          Parsed.new(@entries.values, @clusters)
        end

        private

        def take(line)
          case line
          when /\A## (.+)\z/ then @section = Regexp.last_match(1).strip
          when /\A### (.+)\z/ then @cluster = Regexp.last_match(1).strip
          else link(line.match(LINK))
          end
        end

        def link(found)
          return unless found
          return cluster(found) if @section == "Clusters"
          return if QUIET.include?(@section)

          status = SECTIONS[@section]
          return @problems << "#{found[:id]} sits under ## #{@section}, which gives no status" unless status

          listed(entry(found, status))
        end

        def listed(entry)
          id = entry.intent_id
          return @problems << "#{id} is listed twice" if @entries.key?(id)

          @entries[id] = entry
        end

        def cluster(found)
          @clusters << Member.new(@cluster, found[:id])
          word = found[:rest].strip.match(MARKER)&.[](:word)
          status = MARKERS[word]
          @marked[found[:id]] ||= Entry.new(found[:id], found[:title], found[:dir], status, nil, nil) if status
        end

        def entry(found, status)
          rest = found[:rest].strip.sub(/\A(?:—|-)\s*/, "")
          dated = %w[done abandoned].include?(status) && rest.match(DATED)
          closed_at, text = dated ? dated.captures : [nil, rest]
          Entry.new(found[:id], found[:title], found[:dir], status, text.to_s.empty? ? nil : text, closed_at)
        end
      end
    end
  end
end
