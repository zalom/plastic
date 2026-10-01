# frozen_string_literal: true

require_relative "../invalid"
require_relative "luhmann_id"

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
      HEADING = /\A(?<level>###?) (?<name>.+)\z/

      # One intent of the file: its status and what its line adds.
      Entry = Data.define(:intent_id, :title, :dir, :status, :disposition, :closed_at)

      # The intent row an entry imports as.
      class Entry
        # `front` holds the fields at the head of the intent's own file.
        def row(front, now)
          { intent_id:, parent_id: LuhmannId.parent_of(intent_id), slug: File.basename(dir).split("--", 2).last,
            title:, kind: front["kind"], status:, disposition:, opened_at: front["created"], closed_at:,
            updated_at: now }
        end
      end

      # One intent's membership of a named cluster.
      Member = Data.define(:name, :intent_id)

      # The entries and clusters of one file.
      Parsed = Data.define(:entries, :clusters)

      # What the import checks and reports.
      class Parsed
        def self.missing_entries(dirs) = dirs.map { |dir| "#{dir} has no entry in INDEX.md" }

        def self.missing_folders(dirs) = dirs.map { |dir| "#{dir} is in INDEX.md and has no folder" }

        # Every intent folder must have an entry and every entry a folder;
        # a guess would import a record nobody wrote.
        def check(dirs)
          listed = entries.map(&:dir)
          problems = Parsed.missing_entries(dirs - listed) + Parsed.missing_folders(listed - dirs)
          raise Invalid, problems.join("; ") if problems.any?

          self
        end

        def counts = { "intents" => entries.size, "clusters" => clusters.size }
      end

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

        def marked_entry = Entry.new(intent_id, found[:title], found[:dir], marked_status, nil, nil)

        private

        def rest = found[:rest].strip

        def detail = rest.sub(/\A(?:—|-)\s*/, "")

        # The date that opens a closed intent's detail, with the text after it.
        def dated = CLOSED.include?(status) ? detail.match(DATED) : nil

        # The disposition and the closing date of the line.
        def closing
          date, text = dated&.captures || [nil, detail]
          [(text unless text.empty?), date]
        end
      end

      module_function

      def parse(text) = Reading.new(links(text)).parsed

      def links(text)
        headings = {}
        text.each_line(chomp: true).filter_map { |line| link(line, headings) }
      end

      def link(line, headings)
        heading = line.match(HEADING)
        headings[heading[:level]] = heading[:name].strip if heading
        found = line.match(Link::PATTERN)
        Link.new(headings["##"], headings["###"], found) if found
      end

      # The links of one file, sorted into entries, clusters and problems.
      class Reading
        def initialize(links)
          @links = links
        end

        def parsed
          problems = unplaced + duplicates
          raise Invalid, "INDEX.md: #{problems.join("; ")}" if problems.any?

          Parsed.new(entries, clustered.map(&:member))
        end

        private

        def clustered = @links.select(&:clustered?)

        def listed = @links.select(&:status)

        # A listed intent comes first; one marked only in a cluster takes its first marker.
        def entries = (listed.map(&:entry) + clustered.select(&:marked_status).map(&:marked_entry)).uniq(&:intent_id)

        def unplaced = @links.reject(&:placed?).map(&:problem)

        def duplicates = listed.map(&:intent_id).tally.select { |_id, count| count > 1 }.keys.map { |id| "#{id} is listed twice" }
      end
    end
  end
end
