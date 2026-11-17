# frozen_string_literal: true

require_relative "../wiring"
require_relative "../graph"

module Plastic
  module Workflows
    # The step the install, the update and the restore share: bring the
    # databases of the home to the newest layout, and say which store stayed
    # behind because its backup failed.
    module SchemaMigration
      def self.bring_current(context, slug: nil)
        report = Graph::SchemaRunner.new(home: context.scope.plastic_home, now: context.now, only: slug).call
        report.failed.each { |store, reason| context.print(line(store, reason)) }
        import_config(context) unless slug
        report
      end

      def self.import_config(context)
        line = Wiring.store(context.scope.plastic_home, clock: context.clock).print_once
        context.print(line) if line
      end

      # The line that says a store stayed behind, for every caller of the runner.
      def self.line(store, reason) = "migrate: #{store} stays behind because #{reason}; fix the cause and run plastic update"
    end
  end
end
