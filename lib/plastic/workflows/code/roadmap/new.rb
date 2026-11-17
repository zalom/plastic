# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Roadmap
        # Creates a roadmap row and offers its first batch.
        class New < CodeWorkflow
          clear_declarations

          gate "roadmap %{slug} already exists", stops: :failure, offers: "plastic roadmap show %{slug}",
            because: "roadmap new creates a roadmap once",
            pass: ->(context) { context.retrieval.roadmaps.find(context.slug).nil? }

          gate "roadmaps/%{slug}.md holds a roadmap this home has no rows for; run plastic sync up to read it", stops: :failure, offers: "plastic sync up",
            because: "roadmaps/%{slug}.md is in the form of this release, and plastic sync up reads it into rows",
            pass: ->(context) { !context.work.roadmap_file_readable?(context.slug) }

          gate "roadmaps/%{slug}.md exists and this home holds no roadmap row for it; no command reads a roadmap file into rows", stops: :failure, offers: "plastic next",
            because: "roadmaps/%{slug}.md is kept as it is, and roadmap new writes no roadmap over a file it holds no row for",
            pass: ->(context) { !context.work.roadmap_file?(context.slug) }

          sets :roadmap

          step "create the roadmap", done: ->(context) { !context.roadmap.nil? },
            changes: { work: "The roadmap is created" } do |context|
            context[:roadmap] = context.work.create_roadmap(context.slug, title: context.title || context.slug, goal: context.goal)
          end

          read "say what was created" do |context|
            context.print("roadmap: #{context.slug} #{context.roadmap.title}")
          end

          outcome :done, offers: "plastic roadmap batch %{slug} 1", because: "roadmap %{slug} exists and has no batch yet"
        end
      end
    end
  end
end
