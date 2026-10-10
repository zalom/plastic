# frozen_string_literal: true

require "varar"
require "fileutils"
require "tmpdir"
require_relative "support/kernel_command"

module LegacyImportAcceptance
  DIR = "store/1--alpha-service"
  INTENTS = "SELECT intent_id || ' ' || status || ' ' || coalesce('since ' || opened_at, 'undated') FROM intents ORDER BY intent_id"

  # Each fixture: what it does to the copied store before the files of 1 are taken.
  FIXTURES = {
    "as written" => ->(_kernel) {},
    "1a without its own file" => lambda do |kernel|
      FileUtils.rm(kernel.path("store/1a--beta-route/1a--beta-route.md"))
    end,
    "a folder with no entry" => ->(kernel) { kernel.write("store/9--stray/spec.md", "# Stray\n") },
    "imported" => ->(kernel) { kernel.run!("sync", "up") }
  }.freeze

  # A copy of the legacy store with the fixture's change, built once per fixture.
  def self.prepare(home, fixture)
    name = fixture.delete_suffix(", folder of 1 deleted")
    KernelCommand.copied(home, name) do |kernel|
      kernel.copy_legacy_store
      FIXTURES.fetch(name).call(kernel)
    end
  end

  # The import line, then how many files were read or printed, so a row stays one line.
  def self.result(call)
    return call.result unless call.code.zero?

    lines = call.said
    counts = { "read" => lines.grep(/\Aread /), "printed" => call.files.split(" / ") - ["none"] }
    rows = [*lines.grep_v(/\Aread /), *counts.reject { |_, found| found.empty? }.map { |verb, found| "#{found.size} files #{verb}" }]
    rows.empty? ? "none" : rows.join(" / ")
  end

  # Whether every file 1 held before the call holds the same bytes after it.
  def self.files(before, after) = (after.slice(*before.keys) == before) ? "byte for byte" : "changed"
end

steps do
  sensor("the fixture, the call, the exit code, the result, the intents and the files of 1") do |_state, row|
    Dir.mktmpdir("varar-legacy-import") do |home|
      kernel = LegacyImportAcceptance.prepare(home, row["fixture"])
      before = kernel.snapshot(LegacyImportAcceptance::DIR)
      FileUtils.rm_rf(kernel.path(LegacyImportAcceptance::DIR)) if row["fixture"].end_with?("deleted")
      call = kernel.run(*row["call"].split)
      intents = kernel.rows("work_graph.db", LegacyImportAcceptance::INTENTS).flatten
      row.merge("exit" => call.code.to_s, "result" => LegacyImportAcceptance.result(call),
        "intents" => intents.empty? ? "none" : intents.join(", "),
        "files of 1" => LegacyImportAcceptance.files(before, kernel.snapshot(LegacyImportAcceptance::DIR)))
    end
  end
end
