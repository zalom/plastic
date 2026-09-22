# frozen_string_literal: true

require_relative "../intent_screen"

module Plastic
  class CLI
    class IntentProgress
      def initialize(scope, id)
        @scope = scope
        @id = id
        @dir = scope.intent_dir(id)
      end

      def decision
        status, = IntentScreen.index_fields(@scope.root, @id)
        return ["none", "the intent is #{status.downcase}"] if %w[Completed Abandoned].include?(status)
        return ["plastic intent step #{@id}", "the graph is ready for its next step"] if File.file?(File.join(@dir, "graph.md"))
        return ["plastic intent spec #{@id}", "write spec.md with the accepted scope"] unless prepared?("spec.md")
        return ["plastic intent spec #{@id}", "write plan.md and checklist.md before execution"] unless prepared?("plan.md") && IntentScreen.items_present?(@dir)

        items = IntentScreen.checklist_items(@dir)
        return ["plastic intent spec #{@id}", "the checklist needs concrete work items"] if items.empty?
        return ["plastic intent verify #{@id}", "all checklist items are complete"] if items.all? { |item| item[:done] }

        ["plastic intent step #{@id}", "the checklist has unfinished work"]
      end

      private

      def prepared?(name)
        path = File.join(@dir, name)
        File.file?(path) && !File.read(path).strip.empty? && !File.read(path).include?(IntentScreen::PLACEHOLDER_SENTINEL)
      end
    end
  end
end
