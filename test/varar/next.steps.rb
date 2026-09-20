# encoding: UTF-8
# frozen_string_literal: true

require "varar"
require "fileutils"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli/commands/next"

BATCH_ONE = <<~TEXT
  # Roadmap: cli and rlm

  ## Batches

  ### Batch 1 the command line foundation

  - [ ] 363 the command line %<first>s
  - [ ] 367 the skill cut %<second>s
TEXT

ROADMAPS = {
  "dispatchable" => format(BATCH_ONE, first: "— queued", second: "— queued"),
  "in flight" => format(BATCH_ONE, first: "— delivering", second: "— queued"),
  "delivered" => format(BATCH_ONE, first: "— delivered", second: "— delivered"),
  "absent" => nil,
}.freeze

steps do
  sensor("the roadmap, the exit code, the result and the reason") do |_state, row|
    Dir.mktmpdir("plastic-varar-next") do |dir|
      fixture = CliFixture.new(dir)
        .global_store(active: [])
        .project("plastic", active: [["363", "The command line"], ["367", "The skill cut"]])
      body = ROADMAPS.fetch(row["roadmap"])
      fixture.roadmap("plastic", "cli-and-rlm", body) if body
      code = Plastic::CLI::Commands::Next.new(["--project", "plastic"], directory: "/nowhere",
                                              **fixture.streams).run
      lines = fixture.printed.lines.map(&:chomp)
      row.merge(
        "exit" => code.to_s,
        "result" => lines.first.to_s.sub(/\Anext work\s+/, ""),
        "because" => lines.find { |line| line.start_with?("because: ") }.to_s.sub("because: ", "")
      )
    end
  end
end
