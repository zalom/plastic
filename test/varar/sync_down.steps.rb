# frozen_string_literal: true

require "varar"
require "fileutils"
require "tmpdir"
require_relative "support/kernel_command"

module SyncDownAcceptance
  SPEC = "store/1--alpha/spec.md"

  # Changes one document row past the command line, as another installation's rows would arrive.
  def self.change_row(kernel, path, body)
    kernel.rows("knowledge_graph.db", "UPDATE documents SET body = '#{body}' || char(10) WHERE path = '#{path}'")
  end

  def self.both_sides(kernel)
    kernel.write(SPEC, "by hand\n")
    change_row(kernel, "spec.md", "in rows")
  end

  CHANGES = {
    "spec row changed" => ->(kernel) { change_row(kernel, "spec.md", "in rows") },
    "spec.md deleted" => ->(kernel) { FileUtils.rm(kernel.path(SPEC)) },
    "intent folder deleted" => ->(kernel) { FileUtils.rm_rf(kernel.path("store/1--alpha")) },
    "spec changed on both sides" => ->(kernel) { both_sides(kernel) },
    "both sides and own file row" => lambda do |kernel|
      both_sides(kernel)
      change_row(kernel, "intent.md", "row only")
    end
  }.freeze

  def self.prepare(kernel, change)
    return kernel.copy_legacy_store if change == "legacy store"

    KernelCommand.alpha(kernel.home)
    CHANGES.fetch(change).call(kernel)
  end

  def self.file(kernel) = File.exist?(kernel.path(SPEC)) ? kernel.read(SPEC).lines.first.chomp : "missing"

  def self.row(kernel) = kernel.rows("knowledge_graph.db", "SELECT body FROM documents WHERE path = 'spec.md'").flatten.first&.chomp || "none"
end

steps do
  sensor("the change, the call, the exit code, the result, the files, the file and the row") do |_state, row|
    Dir.mktmpdir("varar-sync-down") do |home|
      kernel = KernelCommand.new(home)
      SyncDownAcceptance.prepare(kernel, row["change"])
      call = kernel.run(*row["call"].split)
      row.merge("exit" => call.code.to_s, "result" => call.result, "files" => call.files, "file" => SyncDownAcceptance.file(kernel),
        "row" => SyncDownAcceptance.row(kernel))
    end
  end
end
