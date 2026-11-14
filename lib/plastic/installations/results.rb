# frozen_string_literal: true

module Plastic
  module Installations
    # What an install run tells the person: a line for each agent, a table
    # when there is more than one, and the next step.
    class Results
      def initialize(version)
        @version = version
      end

      def print(results, mode)
        puts "\n- Results -\n\n"
        results.each { |result| puts Entry.new(result).line }
        table(results)
        done = results.select { |result| result[:success] }
        finish(done, mode) unless done.empty?
      end

      # One agent's result as the lines and the table row an install prints.
      Entry = Struct.new(:result) do
        def line
          agent = result[:agent]
          return "  #{agent}: already registered, not re-synced (use --reinstall to re-sync)" if result[:skipped]
          return "  #{agent}: #{result[:files]} files installed" if result[:success]

          "   #{agent}: #{result[:reason]}"
        end

        def row
          move = "#{result[:from_version] || "-"} -> #{result[:to_version] || "-"}"
          format("  %-14s %-20s %s", result[:agent], move, status)
        end

        def status
          return "skipped" if result[:skipped]

          result[:success] ? "ok" : "failed"
        end
      end

      private

      def table(results)
        return if results.size <= 1

        puts "\n  Agent          From -> To           Result", "  -----          ----------           ------"
        results.each { |result| puts Entry.new(result).row }
      end

      def finish(done, mode)
        puts "\nPlastic v#{@version} #{(mode == :install) ? "installed" : "re-synced"}."
        puts "   Registered for: #{done.map { |result| result[:agent] }.join(", ")}"
        puts "   Run /clear (or restart your agent) to pick up new conventions."
        puts
        trust(done)
      end

      def trust(done)
        changed = done.flat_map { |result| Array(result[:changed_hooks]) }.uniq
        return if changed.empty?

        puts "   Codex: open Codex, run /hooks, and trust the changed Plastic hooks: #{changed.join(", ")}."
        puts "   Plastic's hooks will not fire until you do.\n\n"
      end
    end
  end
end
