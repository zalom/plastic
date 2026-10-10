# frozen_string_literal: true

module CommandReference
  # The command line of the generator: no argument writes the pages, --check names the pages that are stale.
  class CLI
    def initialize(argv, root:, out: $stdout, build: Build.new(root))
      @argv = argv
      @disk = Disk.new(root)
      @out = out
      @build = build
    end

    def run
      @argv.include?("--check") ? check : write
    end

    private

    def write
      @disk.write(@build.files)
      0
    end

    def check
      stale = Build.stale(@build.files, @disk.files)
      stale.each { |path| @out.puts path }
      stale.empty? ? 0 : 1
    end
  end
end
