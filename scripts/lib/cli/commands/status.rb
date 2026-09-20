# encoding: UTF-8
# frozen_string_literal: true

require_relative "../command"

# `plastic status` - every store this machine holds, the intents each one has
# open, and the one store worth continuing.
#
# The store to continue is chosen by a fixed rule, so two runs never disagree:
# the store whose repository holds the working directory, else the store with
# the most active intents, and on a tie the first in discovery order, which puts
# the global store ahead of the projects and the projects in name order.
module Plastic
  class CLI
    module Commands
      class Status < Command
        USAGE_LINE = "plastic status [--json]"

        private

        def call
          counted.each { |slug, ids| @output.row(slug, summary(ids)) }
          command, because = decision
          @output.next_step(command, because: because)
        end

        def counted
          @counted ||= scope.stores.to_h do |store|
            slug = store[:slug]
            [slug, Scope.new(env: @env, home: @home, slug: slug, directory: @directory).active_ids]
          end
        end

        def summary(ids)
          return "0 active" if ids.empty?

          "#{ids.length} active  #{ids.join(", ")}"
        end

        def decision
          here = scope.directory_project
          return [continue_command(here), "the working directory is inside #{here}"] if busy?(here)

          chosen = busiest
          return ["plastic help", "no store has active work"] unless chosen

          [continue_command(chosen), "#{chosen} holds the most active work, #{intents(chosen)}"]
        end

        def busy?(slug)
          slug && !counted.fetch(slug, []).empty?
        end

        def busiest
          counted.reject { |_slug, ids| ids.empty? }.max_by { |_slug, ids| ids.length }&.first
        end

        def intents(slug)
          count = counted.fetch(slug).length
          count == 1 ? "1 intent" : "#{count} intents"
        end

        def continue_command(slug)
          slug == Scope::GLOBAL ? "plastic continue" : "plastic continue --project #{slug}"
        end
      end
    end
  end
end
