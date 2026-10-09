# frozen_string_literal: true

require "varar"
require "tmpdir"
require_relative "support/kernel_command"

# Imports a legacy store with one roadmap file, gives its first batch a goal
# and done criteria, then walks the batch: the next ready item, its start
# as an intent, and that intent's brief.
module KnowledgeGraphAcceptance
  ROADMAP = <<~MARKDOWN
    # Roadmap: Make It Useful

    ## Goal
    The shop registers every button in the backend.

    ## Waves

    ### Wave 1 — Ship-stopping blockers
    - [ ] 2 Lock down guest order access — queued
    - [ ] 3 Un-nest the wishlist button — queued

    ### Wave 2 — Core commerce
    - [ ] 4 Fix the first-add cart quantity — queued

    ## Graph
    - 2 needs nothing
    - 3 needs nothing
    - 4 needs 2 3
  MARKDOWN

  BATCH_GOAL = ["roadmap", "batch", "make-it-useful", "1", "--goal", "Close the two blockers",
    "--done", "a guest sees only their own order", "--done", "add to cart works on every page"].freeze

  # Each check in walk order; a row runs every check before its own.
  CHECKS = {
    "roadmap next make-it-useful --batch 1" => /\A\S+: \w+\z/,
    "roadmap open make-it-useful 2" => /\Aintent: /,
    "intent brief 2" => /\A(?:goal|criterion): /
  }.freeze

  def self.prepare(home)
    KernelCommand.copied(home, :knowledge_graph) do |kernel|
      kernel.copy_legacy_store
      kernel.write("roadmaps/make-it-useful.md", ROADMAP)
      kernel.run!("sync", "up")
      kernel.run!(*BATCH_GOAL)
    end
  end

  def self.walk_to(kernel, check)
    CHECKS.keys.take_while { |earlier| earlier != check }.each { |earlier| kernel.run!(*earlier.split) }
    kernel.run(*check.split)
  end
end

steps do
  sensor("the step, the exit code and what it shows") do |_state, row|
    Dir.mktmpdir("varar-knowledge-graph") do |home|
      check = row["step"]
      call = KnowledgeGraphAcceptance.walk_to(KnowledgeGraphAcceptance.prepare(home), check)
      lines = call.said.grep(KnowledgeGraphAcceptance::CHECKS.fetch(check))
      row.merge("exit" => call.code.to_s, "shows" => lines.join(", "))
    end
  end
end
