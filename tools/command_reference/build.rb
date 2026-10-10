# frozen_string_literal: true

module CommandReference
  # Builds every reference file in memory: path (from the repository root) to text.
  class Build
    COMMANDS = "docs/reference/commands"
    DSL = "docs/reference/dsl"

    def self.stale(built, disk) = (built.keys | disk.keys).sort.reject { |path| built[path] == disk[path] }

    def initialize(root)
      @root = root
    end

    def files
      model = Model.new(@root)
      pages = Plastic::CLI::TABLE.keys.map { |words| model.page(words) }
      dsl = DslPage.new(model, @root)
      [*pages.flat_map { |page| command_files(page) }, [path(COMMANDS, "README.md"), Markdown::Index.new(pages).to_s], *dsl_files(dsl)].sort.to_h
    end

    private

    def path(*parts) = File.join(*parts)

    def command_files(page)
      folder = path(COMMANDS, page.slug)
      [[path(folder, "README.md"), Markdown::Page.new(page).to_s], *drawings(page).map { |name, svg| [path(folder, name), svg] }]
    end

    def drawings(page)
      shown = page.flows.empty? ? { "call.svg" => Figures::Call.new(page).canvas } : { "chain.svg" => Figures::Chain.new(page).canvas }
      flows = page.flows.to_h { |flow| ["#{flow.key}.svg", Figures::Workflow.new(page, flow).canvas] }
      { "component.svg" => Figures::Component.new(page).canvas, **shown, **flows }.transform_values { |canvas| canvas.to_s(true) }
    end

    def dsl_files(dsl)
      [[path(DSL, "README.md"), DslMarkdown.new(dsl).to_s], *dsl.drawings.map { |name, svg| [path(DSL, name), svg] }]
    end
  end
end
