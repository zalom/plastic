# frozen_string_literal: true

module CommandReference
  # Builds every reference file in memory: path (from the repository root) to text.
  class Build
    COMMANDS = "docs/reference/commands"

    def self.stale(built, disk) = (built.keys | disk.keys).sort.reject { |path| built[path] == disk[path] }

    def initialize(root, table: Plastic::CLI::TABLE)
      @root = root
      @table = table
      @model = Model.new(root, table:)
    end

    def files
      lines = Words.missing(pages)
      raise MissingWords, lines if lines.any?

      built
    end

    private

    def built = [*pages.flat_map { |page| PageFiles.new(page, File.join(COMMANDS, page.slug)).to_a }, index].sort.to_h

    def pages = @pages ||= @table.keys.map { |words| @model.page(words) }

    def index = [File.join(COMMANDS, "README.md"), Markdown::Index.new(pages).to_s]
  end
end
