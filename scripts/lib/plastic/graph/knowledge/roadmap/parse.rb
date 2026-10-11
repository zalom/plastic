# frozen_string_literal: true

require_relative "../roadmap"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # Reads a legacy roadmap file's text into the rows sync up
        # writes: a title and goal, the batches and items of its "## Batches" or
        # "## Waves" section, the "needs" edges of its "## Graph" section, and
        # the dated lines of its "## Log" section. Never raises: a line it
        # cannot read becomes a problem naming the file and the line.
        module Parse
          Batch = Data.define(:position, :title)
          Item = Data.define(:item, :batch, :title, :status)
          LogLine = Data.define(:at, :text)
          Result = Data.define(:title, :goal, :batches, :items, :edges, :log, :problems)

          TOP_HEADING = /\A##\s+(.+?)\s*\z/
          BATCH_HEADING = /\A###\s+(?:Batch|Wave)\s+(\d+)\s*(?:[—-]\s*(.*))?\z/
          ITEM_LEAD = /\A-\s*\[([ xX])\]\s+(\S+)\s+(.*)\z/
          STATUS = /[—-]\s*(queued|delivering|delivered|abandoned|blocked)\b/
          EDGE_LEAD = /\A-\s*(\S+)\s+needs\b(.*)\z/
          TOKEN = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/
          ROOT = "nothing"
          LOG_LEAD = /\A-\s+(\d{4}-\d{2}-\d{2})\s+(.*)\z/
          SECTIONS = { "Batches" => :batches, "Waves" => :batches, "Graph" => :graph, "Log" => :log, "Goal" => :goal }.freeze

          module_function

          def call(text, path:)
            scan = Scan.new(path)
            text.each_line.map(&:chomp).each_with_index { |line, index| scan.line(line, index + 1) }
            scan.finish
            Result.new(title: scan.title, goal: scan.goal, batches: scan.batches, items: scan.items,
              edges: scan.edges, log: scan.log, problems: scan.problems)
          end

          def item(joined, batch:)
            match = joined.match(ITEM_LEAD)
            return [nil, "cannot read roadmap item #{joined.inspect}"] unless match

            status = match[3].match(STATUS)
            return [nil, "no status on roadmap item #{joined.inspect}"] unless status
            return [nil, "not a plain id: #{match[2].inspect}"] unless match[2].match?(TOKEN)

            [Item.new(item: match[2], batch:, title: status.pre_match.strip, status: status[1]), nil]
          end

          def edge_targets(text, line:)
            targets = text.to_s.strip.split(/\s+/)
            problem = edge_problem(targets, line)
            return [nil, problem] if problem

            [(targets == [ROOT]) ? [] : targets, nil]
          end

          def edge_problem(targets, line)
            return "malformed graph line, no target: #{line.inspect}" if targets.empty?
            return "root target mixed with a real target: #{line.inspect}" if targets.include?(ROOT) && targets.length > 1

            bad = targets.find { |target| target != ROOT && !target.match?(TOKEN) }
            "not a plain id #{bad.inspect} on graph line: #{line.inspect}" if bad
          end

          # The scan's own state, one line at a time, so `call` stays a plain loop.
          class Scan
            attr_reader :title, :batches, :items, :edges, :problems, :log

            def initialize(path)
              @path = path
              @goal_lines = []
              @batches = []
              @items = []
              @edges = {}
              @log = []
              @problems = []
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
              match = text.match(BATCH_HEADING)
              return start_batch(match) if match

              stripped = text.strip
              return flush_item if stripped.empty?
              return start_item(stripped, number) if stripped.start_with?("- [")

              @item_buffer << stripped if @item_buffer
            end

            def start_batch(match)
              flush_item
              @current_batch = match[1].to_i
              @batches << Batch.new(position: @current_batch, title: match[2].to_s.strip)
            end

            def start_item(text, number)
              flush_item
              @item_buffer = [text]
              @item_line = number
            end

            def flush_item
              return unless @item_buffer

              joined = @item_buffer.join(" ")
              @item_buffer = nil
              read_item(joined)
            end

            def read_item(joined)
              item, message = Parse.item(joined, batch: @current_batch)
              message ? problem(message, @item_line) : @items << item
            end

            def graph_line(text, number)
              stripped = text.strip
              return if stripped.empty?

              match = stripped.match(EDGE_LEAD)
              return unless match

              read_edge(match, stripped, number)
            end

            def read_edge(match, stripped, number)
              targets, message = Parse.edge_targets(match[2], line: stripped)
              message ? problem(message, number) : @edges[match[1]] = targets
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
  end
end
