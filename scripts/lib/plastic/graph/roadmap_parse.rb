# frozen_string_literal: true

module Plastic
  module Graph
    # Reads a legacy roadmap file's text into the rows sync up
    # writes: a title and goal, the batches and items of its "## Batches" or
    # "## Waves" section, the "needs" edges of its "## Graph" section, and
    # the dated lines of its "## Log" section. Ported from the line patterns
    # of scripts/lib/roadmap_graph.rb and scripts/lib/graph_edges.rb
    # (docs/internals.md names the row shapes a result fills). Never raises:
    # a line it cannot read becomes a problem naming the file and the line.
    module RoadmapParse
      Batch = Data.define(:position, :title)
      Item = Data.define(:item, :batch, :title, :status)
      LogLine = Data.define(:at, :text)
      Result = Data.define(:title, :goal, :batches, :items, :edges, :log, :problems)

      TOP_HEADING = /\A##\s+(.+?)\s*\z/.freeze
      BATCH_HEADING = /\A###\s+(?:Batch|Wave)\s+(\d+)\s*(?:[—-]\s*(.*))?\z/.freeze
      ITEM_LEAD = /\A-\s*\[([ xX])\]\s+(\S+)\s+(.*)\z/.freeze
      STATUS = /[—-]\s*(queued|delivering|delivered|abandoned|blocked)\b/.freeze
      EDGE_LEAD = /\A-\s*(\S+)\s+needs\b(.*)\z/.freeze
      TOKEN = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/.freeze
      ROOT = "nothing"
      LOG_LEAD = /\A-\s+(\d{4}-\d{2}-\d{2})\s+(.*)\z/.freeze
      SECTIONS = { "Batches" => :batches, "Waves" => :batches, "Graph" => :graph, "Log" => :log, "Goal" => :goal }.freeze

      module_function

      def call(text, path:)
        scan = Scan.new(path)
        text.each_line.map(&:chomp).each_with_index { |line, index| scan.line(line, index + 1) }
        scan.finish
        Result.new(title: scan.title, goal: scan.goal, batches: scan.batches, items: scan.items,
          edges: scan.edges, log: scan.log, problems: scan.problems)
      end

      # The scan's own state, one line at a time, so `call` stays a plain loop.
      class Scan
        attr_reader :title, :batches, :items, :edges, :problems, :log

        def initialize(path)
          @path = path
          @title = nil
          @state = nil
          @goal_lines = []
          @batches = []
          @items = []
          @edges = {}
          @log = []
          @problems = []
          @current_batch = nil
          @item_buffer = nil
          @log_buffer = nil
        end

        def goal = @goal_lines.join(" ").strip.empty? ? nil : @goal_lines.map(&:strip).join(" ")

        def line(text, number)
          @title ||= text[/\A#\s+(?:Roadmap:\s*)?(.*)\z/, 1]&.strip
          return enter_section(text) if text.match?(TOP_HEADING)

          dispatch(text, number)
        end

        def finish
          flush_item
          flush_log
        end

        private

        def enter_section(text)
          flush_item
          flush_log
          @state = SECTIONS[text[TOP_HEADING, 1]]
        end

        def dispatch(text, number)
          case @state
          when :goal then @goal_lines << text unless text.strip.empty?
          when :batches then batch_line(text, number)
          when :graph then graph_line(text, number)
          when :log then log_line(text, number)
          end
        end

        def batch_line(text, number)
          if (match = text.match(BATCH_HEADING))
            flush_item
            @current_batch = match[1].to_i
            @batches << Batch.new(position: @current_batch, title: match[2].to_s.strip)
          elsif text.strip.start_with?("- [")
            flush_item
            @item_buffer = [text.strip]
            @item_line = number
          elsif text.strip.empty?
            flush_item
          elsif @item_buffer
            @item_buffer << text.strip
          end
        end

        def flush_item
          return unless @item_buffer

          joined = @item_buffer.join(" ")
          @item_buffer = nil
          read_item(joined)
        end

        def read_item(joined)
          match = joined.match(ITEM_LEAD)
          return problem("cannot read roadmap item #{joined.inspect}", @item_line) unless match

          status = match[3].match(STATUS)
          return problem("no status on roadmap item #{joined.inspect}", @item_line) unless status
          return problem("not a plain id: #{match[2].inspect}", @item_line) unless match[2].match?(TOKEN)

          @items << Item.new(item: match[2], batch: @current_batch, title: status.pre_match.strip, status: status[1])
        end

        def graph_line(text, number)
          stripped = text.strip
          return if stripped.empty?

          match = stripped.match(EDGE_LEAD)
          return unless match

          read_edge(match, stripped, number)
        end

        def read_edge(match, stripped, number)
          id = match[1]
          targets = match[2].to_s.strip.split(/\s+/)
          return problem("malformed graph line, no target: #{stripped.inspect}", number) if targets.empty?
          return problem("root target mixed with a real target: #{stripped.inspect}", number) if targets.include?(ROOT) && targets.length > 1

          bad = targets.find { |target| target != ROOT && !target.match?(TOKEN) }
          return problem("not a plain id #{bad.inspect} on graph line: #{stripped.inspect}", number) if bad

          @edges[id] = (targets == [ROOT]) ? [] : targets
        end

        # A bullet at the margin opens a log line; an indented one continues it.
        def log_line(text, number)
          if text.start_with?("- ")
            flush_log
            @log_buffer = [text.strip]
            @log_line = number
          elsif text.strip.empty?
            flush_log
          elsif @log_buffer
            @log_buffer << text.strip
          end
        end

        def flush_log
          return unless @log_buffer

          joined = @log_buffer.join(" ")
          @log_buffer = nil
          match = joined.match(LOG_LEAD)
          return problem("cannot read log line #{joined.inspect}", @log_line) unless match

          @log << LogLine.new(at: match[1], text: match[2].strip)
        end

        def problem(message, number) = @problems << "#{@path}:#{number}: #{message}"
      end
    end
  end
end
