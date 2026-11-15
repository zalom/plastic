# frozen_string_literal: true

module CommandReference
  # Every file of one command page: its README and its two drawings.
  class PageFiles
    def initialize(page, folder)
      @page = page
      @folder = folder
    end

    def to_a = [[File.join(@folder, "README.md"), Markdown::Page.new(@page).to_s], *drawings.map { |name, svg| [File.join(@folder, name), svg] }]

    private

    def drawings = { **overview, "events.svg" => Figures::Events.new(@page).canvas }.transform_values(&:standalone)

    def overview = (@page.flows.size > 1) ? { "workflows.svg" => Figures::Overview.new(@page).canvas } : {}
  end
end
