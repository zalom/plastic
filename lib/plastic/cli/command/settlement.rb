# frozen_string_literal: true

require_relative "../../errors"
require_relative "../../graph/missing_store"
require_relative "../../graph/behind"
require_relative "../offer"

module Plastic
  class CLI
    class Command
      # How a call that stopped ends: the rows it wrote print first, then the
      # error line, and the exit code says which kind of stop it was.
      class Settlement
        def initialize(output, usage_line, workspace)
          @output = output
          @usage_line = usage_line
          @workspace = workspace
        end

        def settle(error)
          message = error.message
          case error
          when Refused, Failed then stop(error)
          when Graph::OutOfStep then stop(Refused.new(message, next_command: error.next_command))
          when Graph::MissingStore then stop(Failed.new(message, next_command: error.next_command(@workspace.scope.projects[error.store])))
          else usage(error)
          end
        end

        def broken(error)
          @output.flush unless @output.json?
          @output.failed(error.message)
          Command::FAILED
        end

        private

        def usage(error)
          @output.usage(error.message, @usage_line)
          Command::USAGE
        end

        def stop(error)
          slug = @workspace.scope.named_slug
          @output.flush_rows(slug) unless @output.json?
          error.tell(@output, Offer.from(error))
          @output.flush(slug)
          error.exit_code
        end
      end
    end
  end
end
