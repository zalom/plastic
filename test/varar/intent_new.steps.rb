# frozen_string_literal: true

require "varar"
require "tmpdir"
require_relative "support/kernel_command"

module IntentNewAcceptance
  STORES = {
    "empty" => ->(_kernel) {},
    "one intent" => ->(kernel) { kernel.run!("intent", "new", "Parent") },
    "legacy" => ->(kernel) { kernel.copy_legacy_store },
    "index edited by hand" => lambda do |kernel|
      kernel.run!("intent", "new", "First")
      kernel.write("store/index.json", "{}\n")
    end
  }.freeze

  # The intent ids store/index.json lists.
  def self.index(kernel)
    return "none" unless File.exist?(kernel.path("store/index.json"))

    ids = Array(JSON.parse(kernel.read("store/index.json"))["intents"]).map { |intent| intent["intent_id"] }
    ids.empty? ? "none" : ids.join(", ")
  end

  # The files of the intent the call wrote.
  def self.files(kernel, call)
    id = call.out[/\Aintent: (\S+)/, 1]
    return "none" unless id

    Dir.children(Dir[kernel.path("store/#{id}--*")].first).sort.join(", ")
  end

  def self.says(call)
    return call.reason unless call.code.zero?

    call.said.find { |line| line.start_with?("ref: ") } || call.out[/^because: (.*)$/, 1]
  end
end

steps do
  sensor("the store, the call, the exit code, the index, the files and what it says") do |_state, row|
    Dir.mktmpdir("varar-intent-new") do |home|
      kernel = KernelCommand.new(home)
      IntentNewAcceptance::STORES.fetch(row["store"]).call(kernel)
      words = row["call"].split.map { |word| word.sub("ORIGIN") { kernel.origin } }
      call = kernel.run("intent", "new", *words)
      row.merge("exit" => call.code.to_s, "index" => IntentNewAcceptance.index(kernel),
        "files" => IntentNewAcceptance.files(kernel, call), "says" => IntentNewAcceptance.says(call))
    end
  end
end
