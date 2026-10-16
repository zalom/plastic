# frozen_string_literal: true

module CommandReference
  # Every file of one command page: its README and its drawings.
  class PageFiles
    def initialize(page, folder)
      @page = page
      @folder = folder
    end

    def to_a = [[File.join(@folder, "README.md"), Markdown::Page.new(@page).to_s], *drawings.map { |name, svg| [File.join(@folder, name), svg] }]

    private

    def drawings = { "component.svg" => Figures::Component.new(@page).canvas, "touches.svg" => Figures::Touches.new(@page).canvas, **overview, **flows }.transform_values(&:standalone)

    def overview
      return { "call.svg" => Figures::Call.new(@page).canvas } if @page.flows.empty?

      (@page.flows.size > 1) ? { "workflows.svg" => Figures::Workflows.new(@page).canvas } : {}
    end

    def flows = @page.flows.to_h { |flow| ["#{flow.key}.svg", Figures::Workflow.new(@page, flow).canvas] }
  end
end
