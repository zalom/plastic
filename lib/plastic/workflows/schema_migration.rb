# frozen_string_literal: true

require_relative "../graph"

module Plastic
  module Workflows
    # The step the install, the update and the restore share: bring the
    # databases of the home to the newest layout, and say which store stayed
    # behind because its backup failed.
    module SchemaMigration
      def self.bring_current(context, slug: nil)
        report = Graph::SchemaRunner.new(home: context.scope.plastic_home, only: slug).call
        report.failed.each { |store| context.print("migrate: #{store} stays behind because its backup failed; fix the cause and run plastic update") }
        report
      end
    end
  end
end
