# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"

module Plastic
  # Generates public benchmark input and records whole-process command timings.
  module RetrievalBenchmark
    ROOT = File.expand_path("..", __dir__)
    SCHEMA_PATH = File.join(__dir__, "retrieval_benchmark_schema.json")
    TEXT = "Plastic retrieval benchmark prose: common context terms and a rare marker. Živjeli.\n"

    module_function

    def schema = JSON.parse(File.read(SCHEMA_PATH))

    def generate_corpus(directory, target_bytes:, stores: 3)
      FileUtils.mkdir_p(directory)
      corpus_receipt(corpus_paths(directory, target_bytes, stores))
    end

    def run(output:, corpus_bytes: 15_000_000, warmup: schema.dig("warmup_samples", "warmup"), samples: schema.dig("warmup_samples", "samples"))
      Dir.mktmpdir("plastic-retrieval-benchmark") do |directory|
        corpus = generate_corpus(File.join(directory, "corpus"), target_bytes: corpus_bytes, stores: 3)
        commands = benchmark_commands(warmup, samples)
        report = report_for(corpus, commands, warmup, samples)
        File.write(output, JSON.pretty_generate(report) + "\n")
        report
      end
    end

    def benchmark_commands(warmup, samples)
      schema.fetch("measurements").to_h do |measurement|
        command = [RbConfig.ruby, File.join(ROOT, "bin", "plastic"), "--help"]
        warmup.times { run_command(command) }
        [measurement.fetch("id"), samples.times.map { run_command(command) }]
      end
    end

    def run_command(command)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = Open3.capture3({ "RUBYOPT" => "" }, *command)
      { "started_at" => Time.now.utc.iso8601, "duration_ms" => ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3),
        "exit_status" => status.exitstatus, "stdout_sha256" => Digest::SHA256.hexdigest(stdout), "stderr_sha256" => Digest::SHA256.hexdigest(stderr) }
    end

    def report_for(corpus, commands, warmup, samples)
      { "schema_version" => schema.fetch("schema_version"), "generated_at" => Time.now.utc.iso8601,
        "hardware" => { "ruby" => RUBY_DESCRIPTION, "platform" => RUBY_PLATFORM, "cpu" => `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip, "memory_bytes" => `sysctl -n hw.memsize 2>/dev/null`.strip },
        "cache" => schema.dig("warmup_samples", "cache"), "warmup" => warmup, "samples" => samples, "corpus" => corpus,
        "targets_ms" => schema.fetch("warm_p95_targets_ms"), "measurements" => commands,
        "owner_review" => { "status" => "pending", "reason" => "Synthetic corpus measurements do not satisfy the owner-reviewed quality gate." } }
    end

    def write_store(directory, index, size)
      store = File.join(directory, "store-#{index + 1}")
      FileUtils.mkdir_p(store)
      path = File.join(store, "document.md")
      body = (TEXT * (size / TEXT.bytesize + 1)).byteslice(0, size)
      File.binwrite(path, body)
      path
    end

    def corpus_paths(directory, target_bytes, stores)
      stores.times.map { |index| write_store(directory, index, bytes_for_store(index, target_bytes, stores)) }
    end

    def bytes_for_store(index, target_bytes, stores)
      target_bytes / stores + ((index < target_bytes % stores) ? 1 : 0)
    end

    def corpus_receipt(paths)
      { "bytes" => paths.sum { |path| File.size(path) }, "documents" => paths.length,
        "stores" => paths.map { |path| File.basename(File.dirname(path)) }, "files" => paths,
        "sha256" => Digest::SHA256.hexdigest(paths.map { |path| File.binread(path) }.join) }
    end
  end
end
