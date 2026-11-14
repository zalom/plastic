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
        results.each { |result| puts line(result) }
        table(results)
        done = results.select { |result| result[:success] }
        finish(done, mode) unless done.empty?
      end

      private

      def line(result)
        return "  ℹ  #{result[:agent]}: already registered, not re-synced (use --reinstall to re-sync)" if result[:skipped]
        return "  #{result[:agent]}: #{result[:files]} files installed" if result[:success]

        "   #{result[:agent]}: #{result[:reason]}"
      end

      def table(results)
        return if results.size <= 1

        puts "\n  Agent          From → To            Result", "  -----          -----------      ------"
        results.each { |result| puts row(result) }
      end

      def row(result)
        move = "#{result[:from_version] || "-"} → #{result[:to_version] || "-"}"
        format("  %-14s %-16s %s", result[:agent], move, status(result))
      end

      def status(result)
        return "skipped" if result[:skipped]

        result[:success] ? "ok" : "failed"
      end

      def finish(done, mode)
        puts "\nPlastic v#{@version} #{mode == :install ? "installed" : "re-synced"}."
        puts "   Registered for: #{done.map { |result| result[:agent] }.join(", ")}"
        puts "   Run /clear (or restart your agent) to pick up new conventions."
        puts "   Next: run plastic help tutorial\n\n"
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
