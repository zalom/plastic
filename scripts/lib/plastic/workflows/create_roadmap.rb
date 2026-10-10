# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Creates a roadmap row and offers its first batch.
    class CreateRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      gate "roadmap %{slug} already exists", stops: :failure, offers: "plastic roadmap show %{slug}",
        because: "roadmap new creates a roadmap once",
        pass: ->(context) { context.retrieval.roadmap(context.slug).nil? }

      sets :roadmap

      step "create the roadmap", done: ->(context) { !context.roadmap.nil? } do |context|
        context[:roadmap] = context.work.create_roadmap(context.slug, title: context.title || context.slug, goal: context.goal)
      end

      read "say what was created" do |context|
        context.print("roadmap: #{context.slug} #{context.roadmap.title}")
      end

      outcome :done, offers: "plastic roadmap batch %{slug} 1", because: "roadmap %{slug} exists and has no batch yet"
    end
  end
end
