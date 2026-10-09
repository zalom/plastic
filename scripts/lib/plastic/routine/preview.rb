# frozen_string_literal: true

require "shellwords"
require_relative "preview_output"
require_relative "../graph/disposable_copy"

module Plastic
  class Routine < CLI::Command
    # `previews` in a routine's class body gives the call a --dry-run switch.
    # A previewed call runs its whole chain in a disposable copy of the
    # store and says what it would have written; the original is never
    # touched. A chain with an agent workflow cannot preview, because the
    # agent's steps run outside the copy.
    module Preview
      # The class-body words.
      module Declaration
        def previews
          option :dry_run, switch: "--dry-run", text: "preview the call in a disposable copy", default: false
          @previews = true
        end

        def previews? = @previews == true

        def preview_problems
          return [] unless previews?

          chain.keys.select { |key| chain.fetch(key).lane == "agent" }
            .map { |key| "#{key} is an agent workflow, and a call that previews cannot run one" }
        end
      end

      private

      def run_chain
        finish(open_routine_run)
      rescue Graph::Database::Error => error
        raise CLI::Command::Failure, error.message
      end

      def previewing? = self.class.previews? && parsed[:dry_run]

      def preview
        Graph::DisposableCopy.new(scope.plastic_home, scope.slug).within { |copy| preview_in(copy) }
      rescue Graph::DisposableCopy::Refused => error
        output.raw(PreviewOutput::CLOSING)
        raise CLI::Command::Refusal, error.message
      end

      def preview_in(copy)
        enter(copy)
        run_shown(copy)
      rescue CLI::Command::Refusal, CLI::Command::Failure => error
        raise error.rebuilt(copy.original(error.message))
      ensure
        leave
      end

      def run_shown(copy)
        run_chain
      ensure
        output.show(copy.changes)
      end

      def enter(copy)
        @kept = [@scope, @graphs]
        @output = PreviewOutput.new(output, copy, original_command)
        @scope = CLI::Scope.new(env: environment.env.to_h.merge("PLASTIC_HOME" => copy.path), home: environment.home, slug: scope.slug,
          directory: environment.directory)
        @graphs = nil
      end

      def leave = (@scope, @graphs = @kept)

      def preview_facts = parsed[:dry_run] ? { original_command: } : {}

      def original_command = Shellwords.join(["plastic", *words.to_s.split, *@argv.reject { |word| word == "--dry-run" }])
    end
  end
end
